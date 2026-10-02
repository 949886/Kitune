"""Audit every serialized camera region and export relocatable Godot presets.

Unlike the native level filter, retain disabled instances for explicit activation.
Only the prefab/level headers establish presence; decompiled types alone do not.
"""
import argparse
import hashlib
import json
from pathlib import Path
from import_inari import Importer, UnityPy


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    package = root / 'Samples/INARIMechanisms'
    catalog_path = root / 'Samples/ArtDirection/Original/INARI/mechanism_catalog.json'
    rules_path = root / 'Samples/ArtDirection/Original/INARI/camera_zones.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    native = json.loads(rules_path.read_text(encoding='utf8'))
    camera_path = root / 'Samples/ArtDirection/Original/INARI/camera.json'
    camera = json.loads(camera_path.read_text(encoding='utf8'))
    assert camera['sha256'] == hashlib.sha256((source / camera['source']).read_bytes()).hexdigest()
    for name, digest in catalog['source_sha256'].items():
        assert hashlib.sha256((source / name).read_bytes()).hexdigest() == digest, name
    imp = Importer(source, root / 'tmp/art-direction/camera-zone-export')
    types = {'CameraDistanceTrigger', 'CameraFixTargetTrigger'}
    absent_observers = {'MoveBeforeSceneObserver', 'MoveStageSceneObserver', 'MoveHubStageSceneObserver'}
    headers, records, hashes = [], {}, dict(catalog['source_sha256'])

    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8', newline='\n')

    for path in sorted([*source.glob('level[0-9]*'), *source.glob('*.assets')]):
        env = UnityPy.load(str(path))
        env.typetree_generator = imp.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == path.name}
        found = []
        for obj in objects.values():
            if obj.type.name != 'MonoBehaviour':
                continue
            name = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
            assert name not in absent_observers, (path.name, obj.path_id, name)
            if name in types:
                found.append(obj.path_id)
        entries = [e for e in catalog['scenes'].get(path.name, []) if e['type'] in types]
        assert set(found) == {int(e['component_id']) for e in entries}, path.name
        headers.append(dict(file=path.name, ids=found))
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        for entry in entries:
            fields = objects[int(entry['component_id'])].read_typetree()
            assert fields == entry['fields']
            box_id = int(fields['boxCollider2D']['m_PathID'])
            box = objects[box_id].read_typetree()
            assert box == next(c['data'] for c in entry['colliders'] if int(c['component_id']) == box_id)
            assert box['m_IsTrigger']
            key = f'{path.name}_{entry["component_id"]}'
            fixed = entry['type'] == 'CameraFixTargetTrigger'
            active = bool(entry['active'] and entry['enabled'] and box['m_Enabled'])
            values = dict(kind=int(fixed), trigger_size=[box['m_Size'][a] * 16 for a in 'xy'],
                          trigger_offset=[box['m_Offset']['x'] * 16, -box['m_Offset']['y'] * 16],
                          initially_active=active, once=bool(fields['isOnce']))
            if fixed:
                values.update(blend=[fields['xDamp'], fields['yDamp']], distance=fields['distance'])
            else:
                values.update(tracked_offset=[fields['offset'][a] for a in 'xyz'], damping=fields['damping'])
            records[key] = dict(source=entry, box=box, settings=values)
            lines = ['[gd_resource type="Resource" load_steps=2 format=3]', '',
                     '[ext_resource type="Script" path="../ZoneSettings.gd" id="1"]', '',
                     '[resource]', 'script = ExtResource("1")']
            for name, value in values.items():
                text = f'Vector{len(value)}(' + ', '.join(map(str, value)) + ')' if isinstance(value, list) else str(value).lower()
                lines.append(f'{name} = {text}')
            lines.append('source_transform = Transform2D(' + ', '.join(map(str, entry['spatial']['transform'])) + ')')
            write(package / f'Devices/CameraZone/Presets/{key}.tres', '\n'.join(lines) + '\n')
    behavior = {}
    for name, expected in native['source_sha256'].items():
        path = root / 'tmp/art-direction/decompiled' / name
        if not path.exists():
            path = root / 'tmp/art-direction' / name
        behavior[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        assert behavior[name] == expected, name
    evidence = dict(records=records, rules=native['rules'], source_sha256=hashes,
                    behavior_sha256=behavior, scanned_headers=headers,
                    absent_serialized_types=sorted(absent_observers),
                    input_sha256={p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in [catalog_path, rules_path, camera_path]})
    write(package / 'Assets/CameraZone/device.json', json.dumps(evidence, ensure_ascii=False, separators=(',', ':')) + '\n')
    write(package / 'Assets/CameraZone/camera.json', camera_path.read_text(encoding='utf8'))
    print('PORTABLE_CAMERA_EXPORT', len(records), 'regions;', sum(r['settings']['initially_active'] for r in records.values()), 'initially active;', len(headers), 'files audited')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
