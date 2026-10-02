"""Create all source audio-zone settings inside the portable copy boundary."""
import hashlib
import json
from pathlib import Path


def export():
    root = Path(__file__).resolve().parents[3]
    package = root / 'Samples/INARIMechanisms'
    catalog = root / 'Samples/ArtDirection/Original/INARI/environment_audio.json'
    document = json.loads(catalog.read_text(encoding='utf8'))
    folder = package / 'Devices/EnvironmentAudio'
    (folder / 'Presets').mkdir(parents=True, exist_ok=True)
    family = {'AmbientParameterTrigger': 'ambient', 'BGMParameterTrigger': 'bgm', 'ReverbParameterTrigger': 'reverb'}
    for scene, rows in document['levels'].items():
        for row in rows:
            source, fields = row['source'], row['fields']
            box = source['colliders'][0]['data']
            assert row['audit']['roundtrip_equal'] and box['m_IsTrigger']
            settings = dict(family=family[source['type']], event_guid=row['resolved_event_guid'],
                parameters=row['parameters'], once=bool(fields['once']), source_layer_bits=int(fields['triggerLayer']['m_Bits']),
                initially_active=bool(source['active'] and source['enabled'] and box['m_Enabled']), persistence_id=fields['id'])
            lines = ['[gd_resource type="Resource" load_steps=2 format=3]', '',
                     '[ext_resource type="Script" path="../AudioZoneSettings.gd" id="1"]',
                     '', '[resource]', 'script = ExtResource("1")']
            for name, value in settings.items(): lines.append(f'{name} = {json.dumps(value, ensure_ascii=False)}')
            lines.extend([f'trigger_size = Vector2({box["m_Size"]["x"] * 16}, {box["m_Size"]["y"] * 16})',
                f'trigger_offset = Vector2({box["m_Offset"]["x"] * 16}, {-box["m_Offset"]["y"] * 16})',
                'source_transform = Transform2D(' + ', '.join(map(str, source['spatial']['transform'])) + ')'])
            (folder / f'Presets/{scene}_{source["component_id"]}.tres').write_text('\n'.join(lines) + '\n', encoding='utf8', newline='\n')
    document['portable_input_sha256'] = {catalog.relative_to(root).as_posix(): hashlib.sha256(catalog.read_bytes()).hexdigest()}
    output = package / 'Assets/EnvironmentAudio/device.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf8', newline='\n')
    for name, preset in [('AmbientZone', 'level15_11051'), ('BGMZone', 'level15_11102'), ('ReverbZone', 'level15_11040')]:
        (folder / f'{name}.tscn').write_text(f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="AudioParameterZone.gd" id="1"]
[ext_resource type="Resource" path="Presets/{preset}.tres" id="2"]

[node name="{name}" type="Area2D"]
script = ExtResource("1")
settings = ExtResource("2")
''', encoding='utf8', newline='\n')
    print('PORTABLE_ENVIRONMENT_EXPORT', sum(map(len, document['levels'].values())), 'presets')


if __name__ == '__main__': export()
