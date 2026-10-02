"""Audit every serialized range trigger and export portable source presets."""
import argparse
import hashlib
import json
from pathlib import Path
from import_inari import UnityPy, TypeTreeGenerator
from unity_parameter_triggers import decode
from unity_scene_spatial import WorldTransforms


def export(source):
    root = Path(__file__).resolve().parents[3]
    package = root / 'Samples/INARIMechanisms'
    catalog_path = root / 'Samples/ArtDirection/Original/INARI/mechanism_catalog.json'
    controls_path = root / 'Samples/ArtDirection/Original/INARI/controls.json'
    asset_audit_path = root / 'Samples/ArtDirection/Original/INARI/mechanism_asset_audit.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    controls = json.loads(controls_path.read_text(encoding='utf8'))
    asset_audit = json.loads(asset_audit_path.read_text(encoding='utf8'))
    assert not asset_audit['errors'] and 'ShurikenDistanceTrigger' in asset_audit['candidates']
    assert not any(r['type'] == 'ShurikenDistanceTrigger' for r in asset_audit['records'])
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    source_hashes = {**catalog['source_sha256'], **controls['source_sha256'], **asset_audit['source_sha256']}
    for name, digest in source_hashes.items():
        assert sha(source / name) == digest, name
    generator = TypeTreeGenerator('2022.3.62f3')
    generator.load_local_game(str(source.parent))
    records, headers, hashes = {}, [], dict(source_hashes)
    folder = package / 'Devices/ShurikenDistance'
    (folder / 'Presets').mkdir(parents=True, exist_ok=True)
    for path in sorted([*source.glob('level[0-9]*'), *source.glob('*.assets')]):
        env = UnityPy.load(str(path)); env.typetree_generator = generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == path.name}
        found = [o.path_id for o in objects.values() if o.type.name == 'MonoBehaviour'
                 and o.parse_monobehaviour_head().m_Script.read().m_ClassName == 'ShurikenDistanceTrigger']
        entries = [e for e in catalog['scenes'].get(path.name, []) if e['type'] == 'ShurikenDistanceTrigger']
        assert set(found) == {int(e['component_id']) for e in entries}, path.name
        headers.append(dict(file=path.name, ids=found)); hashes[path.name] = sha(path)
        if not entries: continue
        transforms = {o.path_id: o.read_typetree() for o in objects.values() if o.type.name == 'Transform'}
        by_go = {t['m_GameObject']['m_PathID']: tid for tid, t in transforms.items()}
        world = WorldTransforms(transforms)
        for entry in entries:
            fields, audit = decode(objects[int(entry['component_id'])], {'ShurikenDistanceTrigger'})
            # Historical catalog predates the MonoBehaviour header alignment fix.
            for key in fields.keys() - {'m_GameObject', 'm_Enabled', 'm_Script', 'm_Name'}:
                assert fields[key] == entry['fields'][key], key
            assert world.sprite_plane(by_go[int(entry['go'])], controls['pixels_per_unit']) == entry['spatial']
            assert len(entry['colliders']) == 1
            box = objects[int(entry['colliders'][0]['component_id'])].read_typetree()
            assert box == entry['colliders'][0]['data'] and box['m_IsTrigger']
            for name in ['enterEvent', 'exitEvent', 'loadEvent']:
                assert not fields[name]['m_PersistentCalls']['m_Calls']
            key = f'{path.name}_{entry["component_id"]}'
            records[key] = dict(source=entry, fields=fields, box=box, audit=audit)
            values = dict(additive_distance=fields['additiveDistance'], once=bool(fields['once']),
                          source_layer_bits=int(fields['triggerLayer']['m_Bits']), persistence_id=fields['id'],
                          initially_active=bool(entry['active'] and entry['enabled'] and box['m_Enabled']))
            lines = ['[gd_resource type="Resource" load_steps=2 format=3]', '',
                     '[ext_resource type="Script" path="../DistanceSettings.gd" id="1"]', '',
                     '[resource]', 'script = ExtResource("1")']
            lines += [f'{name} = {json.dumps(value)}' for name, value in values.items()]
            ppu = controls['pixels_per_unit']
            lines += [f'trigger_size = Vector2({box["m_Size"]["x"] * ppu}, {box["m_Size"]["y"] * ppu})',
                      f'trigger_offset = Vector2({box["m_Offset"]["x"] * ppu}, {-box["m_Offset"]["y"] * ppu})',
                      'source_transform = Transform2D(' + ', '.join(map(str, entry['spatial']['transform'])) + ')']
            (folder / f'Presets/{key}.tres').write_text('\n'.join(lines) + '\n', encoding='utf8', newline='\n')
    assert len(records) == 2
    baseline = dict(base_distance=controls['combat']['ShurikenMaxDistance'], pixels_per_unit=controls['pixels_per_unit'],
                    flight_speed=controls['projectile']['MoveSpeed'] / controls['projectile_body']['m_Mass'])
    text = '[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="RangeSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    text += ''.join(f'{name} = {value}\n' for name, value in baseline.items())
    (folder / 'DefaultRange.tres').write_text(text, encoding='utf8', newline='\n')
    result = dict(records=records, baseline=baseline, scanned_headers=headers, source_sha256=hashes,
                  input_sha256={p.relative_to(root).as_posix(): sha(p) for p in [catalog_path, controls_path, asset_audit_path]},
                  asset_audit_files=len(asset_audit['source_sha256']),
                  behavior_sha256={n: sha(root / 'tmp/art-direction/decompiled' / n) for n in
                                   ['Trigger.cs', 'ShurikenDistanceTrigger.cs', 'PlayerStateMachine.cs', 'ShurikenObject.cs']})
    destination = package / 'Assets/ShurikenDistance/device.json'; destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf8', newline='\n')
    print('SHURIKEN_DISTANCE_EXPORT_PASS', len(records), 'presets;', len(headers), 'files scanned')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
