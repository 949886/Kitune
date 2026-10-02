"""Export audited ordinary-wave and entrance-contact defaults for portable hosts."""
import copy
import hashlib
import json
from pathlib import Path


def export():
    root = Path(__file__).resolve().parents[3]
    original = root / 'Samples/ArtDirection/Original/INARI'
    package = root / 'Samples/INARIMechanisms'
    profile_path = root / 'Samples/ArtDirection/Profiles/portable_battle.json'
    profile = json.loads(profile_path.read_text(encoding='utf8'))
    machinery_path = original / 'machinery.json'
    machinery = json.loads(machinery_path.read_text(encoding='utf8'))
    battle = machinery['levels'][profile['scene']]['battle']
    source = next(x for x in battle['spawners'] if x['id'] == profile['spawner'])
    contact = next(x for x in battle['contacts'] if x['id'] == profile['contact'])
    fields = source['fields']
    assert not fields['selectedEnemy'] and not fields['timeLine']['m_PathID']
    scene_path = original / (profile['scene'] + '.json')
    scene = json.loads(scene_path.read_text(encoding='utf8'))
    enemies = {int(e['source_id']): e for e in scene['enemies']}
    origin = contact['trigger']['transform'][4:]
    waves, positions, kinds, identities = [], {}, {}, {}
    for index, wave in enumerate(fields['spawnDatas']):
        members = []
        assert len(wave['EnemyPrefab']) == len(wave['SpawnPoint'])
        for number, (ref, point) in enumerate(zip(wave['EnemyPrefab'], wave['SpawnPoint'])):
            key = f'wave_{index + 1}_enemy_{number + 1}'
            members.append(key)
            positions[key] = [point['x'] * 16 - origin[0], -point['y'] * 16 - origin[1]]
            kinds[key] = 'rope' if enemies[int(ref['m_PathID'])]['kind'] == 'EnemyRifleMan' else 'stamp'
            identities[key] = int(ref['m_PathID'])
        waves.append(members)
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8', newline='\n')
    settings = '[gd_resource type="Resource" script_class="" load_steps=2 format=3]\n\n[ext_resource type="Script" path="EncounterSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    settings += f'on_field = {str(bool(fields["IsOnField"])).lower()}\n'
    for prop, value in [('phase_delay', fields['PhaseChangingTime']), ('end_delay', fields['EndTime']), ('arrival_delay', machinery['battle_rules']['spawn_delay']), ('peaceful_delay', fields['waitingTime'])]:
        settings += f'{prop} = {value}\n'
    settings += 'waves = Array[PackedStringArray]([' + ', '.join('PackedStringArray(' + ', '.join(json.dumps(k) for k in wave) + ')' for wave in waves) + '])\n'
    settings += 'placements = {' + ', '.join(json.dumps(k) + f': Vector2({v[0]}, {v[1]})' for k,v in positions.items()) + '}\n'
    settings += 'arrival_kinds = ' + json.dumps(kinds) + '\n'
    settings += f'arrival_offsets = {{"stamp": Vector2(0, {-fields["stampYOffset"] * 16}), "rope": Vector2(0, {-fields["RifleManRopeYOffset"] * 16})}}\n'
    write(package / 'Devices/BattleEncounter/EncounterSettings.tres', settings)
    trigger = contact['trigger']; cf = contact['fields']
    settings = '[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="ContactSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    for prop, value in [('trigger_size', trigger['size']), ('trigger_offset', trigger['offset'])]:
        settings += f'{prop} = Vector2({value[0]}, {value[1]})\n'
    settings += f'once = {str(bool(cf["once"])).lower()}\ndoor_once = {str(bool(cf["isOnce"])).lower()}\n'
    write(package / 'Devices/DoorContact/ContactSettings.tres', settings)
    evidence = dict(profile=profile, source=source, contact=contact, enemy_keys=identities,
                    source_origin=origin, arrival_offsets=dict(stamp=fields['stampYOffset'], rope=fields['RifleManRopeYOffset']),
                    profile_sha256=hashlib.sha256(profile_path.read_bytes()).hexdigest(),
                    input_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [machinery_path,scene_path]},
                    behavior_sha256={name:hashlib.sha256((root/'tmp/art-direction/decompiled'/name).read_bytes()).hexdigest() for name in ['SpawnManager.cs','SpawnData.cs','DoorContactTrigger.cs','MonsterSpawnerTrigger.cs','Trigger.cs']})
    write(package / 'Assets/BattleEncounter/device.json', json.dumps(evidence, ensure_ascii=False, separators=(',', ':'))+'\n')
    print('BATTLE_EXPORT',len(waves),'waves',len(identities),'members')


if __name__ == '__main__':
    export()
