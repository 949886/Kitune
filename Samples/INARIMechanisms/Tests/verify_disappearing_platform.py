"""Verify raw source fields, PCM and copying ONLY the device directory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import wave


def verify(godot, output, source=None):
    package = Path(__file__).resolve().parents[1]
    device = package/'Devices/DisappearingPlatform'
    doc = json.loads((device/'Assets/device.json').read_text(encoding='utf8'))
    assert len(doc['records']) == 14
    assert len({r['component'] for r in doc['records'].values()}) == 5
    for record in doc['records'].values():
        assert record['audit']['roundtrip_equal'] and len(record['cells']) == 6
        assert record['fields']['targetFrame'] == 109 and record['fields']['appearTerm'] == 1.25
        assert [s['name'] for s in record['states']] == ['trap_idle','trap_active','trap_active_idle','trap_recover']
        assert all(s['track']['frame_rate'] == 60 and s['track']['speed'] == 1 for s in record['states'])
        assert all(not s['track'].get('unsupported_bindings') for s in record['states'])
    for name, info in doc['audio']['renders'].items():
        path = device/'Assets'/name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == info['sha256']
        with wave.open(str(path), 'rb') as wav:
            assert wav.getnframes() == info['frames']
            pcm = wav.readframes(wav.getnframes())
            assert any(pcm) and hashlib.sha256(pcm).hexdigest() == info['pcm_sha256']
    if source:
        # Read the serialized bytes independently of the exporter's type tree.
        import sys
        sys.path.insert(0, str(package.parents[1]/'tmp/art-direction/pydeps'))
        import UnityPy
        for name, digest in doc['source_sha256'].items():
            assert hashlib.sha256((source/name).read_bytes()).hexdigest() == digest
        seen = set()
        for record in doc['records'].values():
            identity = (record['source_scene'],record['component'])
            if identity in seen: continue
            seen.add(identity)
            env = UnityPy.load(str(source/identity[0]))
            obj = next(o for o in env.objects if o.assets_file.name == identity[0] and o.path_id == identity[1])
            raw = obj.get_raw_data()
            assert hashlib.sha256(raw).hexdigest() == record['audit']['raw_sha256']
            name_bytes = struct.unpack_from('<I',raw,28)[0]
            offset = (32 + name_bytes + 3) & ~3
            seconds, frame = struct.unpack_from('<fi',raw,offset); offset += 8
            assert seconds == record['fields']['appearTerm'] and frame == record['fields']['targetFrame']
            for field in ['tilemap','tilemapCollider2D','coll']:
                fid,pid = struct.unpack_from('<iq',raw,offset); offset += 12
                assert {'m_FileID':fid,'m_PathID':pid} == record['fields'][field]
            count = struct.unpack_from('<i',raw,offset)[0]; offset += 4
            for index in range(count):
                fid,pid = struct.unpack_from('<iq',raw,offset);offset+=12
                assert {'m_FileID':fid,'m_PathID':pid} == record['fields']['animators'][index]
            assert offset == len(raw)
    project = Path(tempfile.mkdtemp(prefix='standalone-platform-',dir=output.resolve()))
    installed = project/'Nested/RenamedPlatform'
    shutil.copytree(device,installed,ignore=shutil.ignore_patterns('*.uid','*.import','__pycache__'))
    (project/'project.godot').write_text('[application]\nconfig/name="Standalone platform validation"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf8')
    base = [str(godot.resolve()),'--path',str(project),'--headless']
    for name, args, marker in [('import',['--editor','--import','--quit-after','3'],None),
                              ('runtime',['--fixed-fps','60','--script','res://Nested/RenamedPlatform/Tests/StandaloneProbe.gd'],'STANDALONE_DISAPPEARING_PLATFORM_PASS')]:
        result = subprocess.run(base+args+['--log-file',str(project/(name+'.log'))],capture_output=True,encoding='utf8',errors='replace',timeout=60)
        combined = result.stdout+result.stderr
        assert result.returncode == 0 and 'SCRIPT ERROR' not in combined and 'Failed loading resource' not in combined and (marker is None or marker in combined),combined
    print('DISAPPEARING_PLATFORM_SOURCE_AND_COPY_PASS',project,flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('godot',type=Path);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--source',type=Path)
    args=parser.parse_args();verify(args.godot,args.output,args.source)
