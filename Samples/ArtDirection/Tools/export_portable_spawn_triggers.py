"""Export every catalogued MonsterSpawnerTrigger, checking its live target.

The root translation is removed; the authored basis, collider offset/enable
state and timer remain source data. Target IDs are provenance, not runtime
scene-tree lookups. Target waves/thresholds/timelines are separate mechanisms.
"""
import argparse
import hashlib
import json
from pathlib import Path
from import_inari import Importer, UnityPy
from unity_scene_spatial import WorldTransforms


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    original = root / 'Samples/ArtDirection/Original/INARI'
    package = root / 'Samples/INARIMechanisms'
    profile_path = root / 'Samples/ArtDirection/Profiles/portable_spawn_triggers.json'
    profile = json.loads(profile_path.read_text(encoding='utf8'))
    catalog_path = original / 'mechanism_catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    importer = Importer(source, root / 'tmp/art-direction/spawn-trigger-export')
    records, hashes = {}, {}
    global_settings = source / 'globalgamemanagers'
    physics = next(o.read_typetree() for o in UnityPy.load(str(global_settings)).objects if o.type.name == 'Physics2DSettings')
    assert physics['m_CallbacksOnDisable']
    hashes['globalgamemanagers'] = hashlib.sha256(global_settings.read_bytes()).hexdigest()
    folder = package / 'Devices/MonsterSpawnTrigger'
    (folder / 'Presets').mkdir(parents=True, exist_ok=True)
    for level, entries in catalog['scenes'].items():
        selected = [e for e in entries if e['type'] == profile['component_type']]
        if not selected:
            continue
        scene = source / level
        hashes[level] = hashlib.sha256(scene.read_bytes()).hexdigest()
        assert hashes[level] == catalog['source_sha256'][level]
        env = UnityPy.load(str(scene))
        env.typetree_generator = importer.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
        poses = {i: o.read_typetree() for i, o in objects.items() if o.type.name in ['Transform', 'RectTransform']}
        by_go = {p['m_GameObject']['m_PathID']: i for i, p in poses.items()}
        world = WorldTransforms(poses)
        for entry in selected:
            component = objects[int(entry['component_id'])]
            assert component.parse_monobehaviour_head().m_Script.read().m_ClassName == profile['component_type']
            fields = component.read_typetree()
            assert fields == entry['fields']
            assert fields['triggerLayer']['m_Bits'] == 64
            assert all(not fields[k]['m_PersistentCalls']['m_Calls'] for k in ['enterEvent', 'exitEvent', 'loadEvent'])
            collider_id = next(c['component_id'] for c in entry['colliders'] if c['type'] == 'BoxCollider2D')
            collider = objects[int(collider_id)].read_typetree()
            assert collider['m_IsTrigger']
            target_obj = objects[fields['monsterSpawner']['m_PathID']]
            assert target_obj.parse_monobehaviour_head().m_Script.read().m_ClassName == 'SpawnManager'
            target = target_obj.read_typetree()
            pose = world.sprite_plane(by_go[int(entry['go'])], 16)['transform']
            origin = pose[4:]
            pose[4:] = [0, 0]
            size = [collider['m_Size'][a] * 16 for a in 'xy']
            offset = [collider['m_Offset']['x'] * 16, -collider['m_Offset']['y'] * 16]
            key = f'{level}_{entry["component_id"]}'
            record = dict(active=entry['active'], fields=fields, trigger=dict(
                transform=pose, size=size, offset=offset, enabled=bool(collider['m_Enabled'])))
            records[key] = dict(record=record, source_entry=entry, source_origin=origin,
                                source_scene=level, source_id=int(entry['component_id']),
                                target=dict(on_field=bool(target['IsOnField']), waves=len(target['spawnDatas']),
                                            selected_enemies=target['selectedEnemy'], timeline=target['timeLine'],
                                            fields=target, member_kinds={str(ref['m_PathID']): objects[ref['m_PathID']].parse_monobehaviour_head().m_Script.read().m_ClassName
                                                for wave in target['spawnDatas'] for ref in wave['EnemyPrefab']}))
            text = '[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="../SpawnTriggerSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
            text += 'trigger_transform = Transform2D(' + ', '.join(map(str, pose)) + ')\n'
            text += f'trigger_size = Vector2({size[0]}, {size[1]})\ntrigger_offset = Vector2({offset[0]}, {offset[1]})\n'
            for name, value in [('collider_enabled', collider['m_Enabled']), ('initially_active', entry['active']), ('once', fields['once']), ('on_field', target['IsOnField'])]:
                text += f'{name} = {str(bool(value)).lower()}\n'
            text += f'delay_seconds = {fields["spawnTerm"]}\n'
            (folder / 'Presets' / (key + '.tres')).write_text(text, encoding='utf8', newline='\n')
    assert profile['default_preset'] in records
    (folder / 'MonsterSpawnTrigger.tscn').write_text(
        '[gd_scene load_steps=3 format=3]\n\n'
        '[ext_resource type="Script" path="MonsterSpawnTrigger.gd" id="1"]\n'
        f'[ext_resource type="Resource" path="Presets/{profile["default_preset"]}.tres" id="2"]\n\n'
        '[node name="MonsterSpawnTrigger" type="Node2D"]\n'
        'script = ExtResource("1")\nsettings = ExtResource("2")\n',
        encoding='utf8', newline='\n')
    output = package / 'Assets/MonsterSpawnTrigger'
    output.mkdir(parents=True, exist_ok=True)
    evidence = dict(records=records, source_sha256=hashes,
                    profile_sha256=hashlib.sha256(profile_path.read_bytes()).hexdigest(),
                    catalog_sha256=hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
                    behavior_sha256={name: hashlib.sha256((root/'tmp/art-direction/decompiled'/name).read_bytes()).hexdigest() for name in ['MonsterSpawnerTrigger.cs', 'Trigger.cs']},
                    callbacks_on_disable=physics['m_CallbacksOnDisable'],
                    realtime_wait_reference='https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Scripting/WaitForSecondsRealtime.cs')
    (output / 'device.json').write_text(json.dumps(evidence, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
    print('SPAWN_TRIGGER_EXPORT', len(records), 'presets')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
