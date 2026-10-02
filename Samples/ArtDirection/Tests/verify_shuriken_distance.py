"""Independent binary oracle and provenance checks for both range triggers."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import UnityPy
from verify_environment_audio_catalog import Reader


def read_range(raw):
    reader = Reader(raw)
    fields = reader.header()
    fields['triggerLayer'] = {'m_Bits': reader.unpack('I')}
    fields['once'] = reader.unpack('B'); reader.align()
    fields['IsFirstActivated'] = reader.unpack('B'); reader.align()
    for name in ['enterEvent', 'exitEvent', 'loadEvent']: fields[name] = reader.event()
    fields['id'] = reader.string()
    fields['additiveDistance'] = reader.unpack('f')
    assert reader.offset == len(raw)
    return fields


def verify(source):
    root = Path(__file__).resolve().parents[3]
    data = json.loads((root / 'Samples/INARIMechanisms/Assets/ShurikenDistance/device.json').read_text(encoding='utf8'))
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for name, digest in data['source_sha256'].items(): assert sha(source / name) == digest, name
    for name, digest in data['input_sha256'].items(): assert sha(root / name) == digest, name
    for name, digest in data['behavior_sha256'].items(): assert sha(root / 'tmp/art-direction/decompiled' / name) == digest, name
    for key, record in data['records'].items():
        scene, component = key.split('_')
        env = UnityPy.load(str(source / scene))
        obj = next(o for o in env.objects if o.assets_file.name == scene and o.path_id == int(component))
        raw = obj.get_raw_data()
        assert read_range(raw) == record['fields']
        assert hashlib.sha256(raw).hexdigest() == record['audit']['raw_sha256']
        assert len(raw) == record['audit']['bytes']
        for corrupted in [raw[:-1], raw + b'\0']:
            try: read_range(corrupted)
            except (AssertionError, struct.error): pass
            else: raise AssertionError('Malformed range object accepted')
    assert len(data['records']) == 2 and len(data['scanned_headers']) == 60 and data['asset_audit_files'] == 45
    print('SHURIKEN_DISTANCE_INDEPENDENT_PASS', len(data['source_sha256']), 'source files; 2 binary objects')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('source', type=Path)
    verify(parser.parse_args().source)
