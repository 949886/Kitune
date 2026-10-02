"""Export every catalogued selectedEnemy encounter without claiming its AI or Timeline.

The source preset keeps all four waves, placements, thresholds and waits. The
playable host supplies training actors; its platform layout is a separate profile.
"""
import argparse
import hashlib
import json
from pathlib import Path
from import_inari import Importer, UnityPy


def export(source):
    root = Path(__file__).resolve().parents[3]
    original = root/'Samples/ArtDirection/Original/INARI'
    package = root/'Samples/INARIMechanisms'
    profile_path = root/'Samples/ArtDirection/Profiles/portable_threshold_battle.json'
    profile = json.loads(profile_path.read_text(encoding='utf8'))
    catalog_path = original/'mechanism_catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    # Validate the complete inventory before concluding only one encounter uses
    # a selection. Checking level8 alone could hide newly changed other scenes.
    for name, digest in catalog['source_sha256'].items():
        assert hashlib.sha256((source/name).read_bytes()).hexdigest() == digest, name
    machinery_path = original/'machinery.json'
    arrival = json.loads(machinery_path.read_text(encoding='utf8'))['battle_rules']['spawn_delay']
    imp = Importer(source, root/'tmp/art-direction/threshold-export')
    records = {}
    hashes = {}
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8', newline='\n')
    def settings(fields, waves, points, kinds, thresholds, script):
        result = f'[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="{script}" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
        result += f'on_field = {str(bool(fields["IsOnField"])).lower()}\n'
        for name,value in [('phase_delay',fields['PhaseChangingTime']),('end_delay',fields['EndTime']),('arrival_delay',arrival),('peaceful_delay',fields['waitingTime'])]:
            result += f'{name} = {value}\n'
        result += 'waves = Array[PackedStringArray](['+', '.join('PackedStringArray('+', '.join(json.dumps(k) for k in wave)+')' for wave in waves)+'])\n'
        result += 'placements = {'+', '.join(json.dumps(k)+f': Vector2({v[0]}, {v[1]})' for k,v in points.items())+'}\n'
        result += 'arrival_kinds = '+json.dumps(kinds)+'\nthresholds = '+json.dumps(thresholds)+'\n'
        result += f'arrival_offsets = {{"stamp": Vector2(0, {-fields["stampYOffset"]*16}), "rope": Vector2(0, {-fields["RifleManRopeYOffset"]*16})}}\n'
        return result
    for scene,entries in catalog['scenes'].items():
        chosen = [e for e in entries if e['type']=='SpawnManager' and e['fields'].get('selectedEnemy')]
        if not chosen: continue
        hashes[scene] = hashlib.sha256((source/scene).read_bytes()).hexdigest()
        assert hashes[scene] == catalog['source_sha256'][scene]
        env = UnityPy.load(str(source/scene));env.typetree_generator=imp.generator
        objects = {o.path_id:o for o in env.objects if o.assets_file.name==scene}
        for entry in chosen:
            fields = objects[int(entry['component_id'])].read_typetree()
            assert fields == entry['fields']
            origin = entry['spatial']['transform'][4:]
            waves,points,kinds,identities,types = [],{},{},{},{}
            for i,wave in enumerate(fields['spawnDatas']):
                members=[]
                assert len(wave['EnemyPrefab'])==len(wave['SpawnPoint'])
                for n,(ref,point) in enumerate(zip(wave['EnemyPrefab'],wave['SpawnPoint'])):
                    key=f'wave_{i+1}_enemy_{n+1}'
                    members.append(key);identities[key]=ref['m_PathID']
                    types[key]=objects[ref['m_PathID']].parse_monobehaviour_head().m_Script.read().m_ClassName
                    points[key]=[point['x']*16-origin[0],-point['y']*16-origin[1]]
                    kinds[key]='rope' if types[key]=='EnemyRifleMan' else 'stamp'
                waves.append(members)
            reverse={v:k for k,v in identities.items()}
            thresholds={reverse[s['enemyStateMachine']['m_PathID']]:s['hpRatio'] for s in fields['selectedEnemy']}
            key=f'{scene}_{entry["component_id"]}'
            records[key]=dict(source=entry, enemy_keys=identities, enemy_types=types, source_origin=origin, thresholds=thresholds)
            write(package/f'Devices/BattleEncounter/Presets/{key}.tres',settings(fields,waves,points,kinds,thresholds,'../EncounterSettings.gd'))
            if scene==profile['scene'] and int(entry['component_id'])==profile['spawner']:
                assert len(identities)==len(profile['preview_placements'])
                preview=dict(zip(identities,profile['preview_placements']))
                write(package/'Examples/ThresholdSettings.tres',settings(fields,waves,preview,kinds,thresholds,'../Devices/BattleEncounter/EncounterSettings.gd'))
    default=f'{profile["scene"]}_{profile["spawner"]}'
    assert default in records
    write(package/'Devices/BattleEncounter/ThresholdEncounter.tscn',
        '[gd_scene load_steps=3 format=3]\n\n[ext_resource type="Script" path="BattleEncounter.gd" id="1"]\n'
        f'[ext_resource type="Resource" path="Presets/{default}.tres" id="2"]\n\n'
        '[node name="ThresholdEncounter" type="Node2D"]\nscript = ExtResource("1")\nsettings = ExtResource("2")\n')
    evidence=dict(records=records,source_sha256=hashes,
        input_sha256={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [profile_path,catalog_path,machinery_path]},
        behavior_sha256={n:hashlib.sha256((root/'tmp/art-direction/decompiled'/n).read_bytes()).hexdigest()
            for n in ['SpawnManager.cs','SelectedEnemy.cs','InGameEntity.cs','EnemyInGameEntity.cs']})
    write(package/'Assets/ThresholdEncounter/device.json',json.dumps(evidence,ensure_ascii=False,separators=(',',':'))+'\n')
    print('THRESHOLD_EXPORT',len(records),'source encounters;',len(catalog['source_sha256']),'catalog source hashes verified',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    export(parser.parse_args().source)
