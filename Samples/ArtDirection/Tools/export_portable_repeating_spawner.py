"""Audit death-event spawners directly across every serialized scene.

The physics/inheritance catalog does not discover this plain MonoBehaviour.
Keep a separate complete scan (including inactive objects) and file hashes;
absence from the older catalog must never be interpreted as no instances.
Prefab references are provenance. Portable hosts explicitly supply factories.
"""
import argparse
import hashlib
import json
from pathlib import Path
from import_inari import UnityPy, TypeTreeGenerator
from unity_scene_spatial import WorldTransforms


def export(source):
    root = Path(__file__).resolve().parents[3]
    package = root / 'Samples/INARIMechanisms'
    profile_path = root / 'Samples/ArtDirection/Profiles/portable_repeating_spawner.json'
    profile = json.loads(profile_path.read_text(encoding='utf8'))
    generator = TypeTreeGenerator('2022.3.62f3')
    generator.load_local_game(str(source.parent))
    records, hashes = {}, {}
    for path in sorted(source.glob('level*')):
        if not path.name[5:].isdigit():
            continue
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        env = UnityPy.load(str(path))
        env.typetree_generator = generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == path.name}
        selected = [o for o in objects.values() if o.type.name == 'MonoBehaviour'
                    and o.parse_monobehaviour_head().m_Script.read().m_ClassName == profile['component_type']]
        if not selected:
            continue
        poses = {i: o.read_typetree() for i, o in objects.items() if o.type.name == 'Transform'}
        gos = {i: o.read_typetree() for i, o in objects.items() if o.type.name == 'GameObject'}
        by_go = {p['m_GameObject']['m_PathID']: i for i, p in poses.items()}
        world = WorldTransforms(poses)
        for obj in selected:
            fields = obj.read_typetree()
            tid = by_go[fields['m_GameObject']['m_PathID']]
            origin = world.sprite_plane(tid, 16)['transform'][4:]
            active, names, parent = True, [], tid
            while parent:
                pose = poses[parent]
                go = gos[pose['m_GameObject']['m_PathID']]
                active = active and bool(go['m_IsActive'])
                names.insert(0, go['m_Name'])
                parent = pose['m_Father']['m_PathID']
            members = []
            for index, enemy in enumerate(fields['enemyDataList']):
                actor = objects[enemy['stateMachine']['m_PathID']]
                kind = actor.parse_monobehaviour_head().m_Script.read().m_ClassName
                point = enemy['respawnPosition']
                members.append(dict(key=f'enemy_{index+1}', kind=kind,
                    position=[point['x']*16-origin[0], -point['y']*16-origin[1]], source=enemy))
            key = f'{path.name}_{obj.path_id}'
            records[key] = dict(scene=path.name, component=obj.path_id, fields=fields,
                active=active, enabled=bool(fields['m_Enabled']), path='/'.join(names),
                source_origin=origin, members=members)
    default = records[f'{profile["default_scene"]}_{profile["default_component"]}']
    folder = package/'Devices/RepeatingSpawner'
    folder.mkdir(parents=True, exist_ok=True)
    settings = '[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="RepeatSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    settings += f'wait_seconds = {default["fields"]["waitTime"]}\nfade_seconds = {default["fields"]["alphaTime"]}\n'
    settings += 'kinds = '+json.dumps({m['key']: m['kind'] for m in default['members']})+'\n'
    settings += 'placements = {'+', '.join(json.dumps(m['key'])+f': Vector2({m["position"][0]}, {m["position"][1]})' for m in default['members'])+'}\n'
    (folder/'RepeatSettings.tres').write_text(settings, encoding='utf8', newline='\n')
    evidence = dict(profile=profile, profile_sha256=hashlib.sha256(profile_path.read_bytes()).hexdigest(),
        source_sha256=hashes, records=records,
        scope='Every serialized level; indirect death listener, including inactive objects. Runtime-only prefabs are not scanned.',
        behavior_sha256={name:hashlib.sha256((root/'tmp/art-direction/decompiled'/name).read_bytes()).hexdigest()
            for name in ['RepeatingMonsterSpawner.cs', 'EnemyData.cs']})
    output = package/'Assets/RepeatingSpawner'
    output.mkdir(parents=True, exist_ok=True)
    (output/'device.json').write_text(json.dumps(evidence, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
    print('REPEATING_EXPORT', len(hashes), 'scenes', len(records), 'instances', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
