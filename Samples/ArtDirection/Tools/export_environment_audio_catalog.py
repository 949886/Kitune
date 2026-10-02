"""Decode every source audio parameter region and audit its original FMOD event.

This supplements the spatial inventory without rewriting its historical hashes.
It preserves disabled objects, UnityEvents, values, GUIDs and exact geometry.
The exported commands are source evidence, not a baked approximation of mixing.
"""
import argparse
import ctypes as c
import hashlib
import json
import tempfile
import uuid
from collections import Counter
from pathlib import Path

from import_inari import Importer, UnityPy
from import_inari_event_audio import EventRenderer
from unity_parameter_triggers import TYPES, decode, guid_string, runtime_dictionary
from unity_scene_spatial import WorldTransforms

BANKS = ('Master', 'Master.strings', 'AMB', 'BGM', 'Snapshot')


class ParameterID(c.Structure):
    _fields_ = [('data1', c.c_uint), ('data2', c.c_uint)]


class ParameterDescription(c.Structure):
    # FMODUnity.dll / FMOD.Studio.PARAMETER_DESCRIPTION, not the obsolete
    # pyfmodex 1.x declaration (which has an index instead of PARAMETER_ID).
    _fields_ = [('name', c.c_char_p), ('id', ParameterID), ('minimum', c.c_float),
                ('maximum', c.c_float), ('defaultvalue', c.c_float), ('type', c.c_int),
                ('flags', c.c_uint), ('guid', c.c_uint * 4)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def event_metadata(renderer, guid):
    desc = c.c_void_p()
    raw = c.create_string_buffer(uuid.UUID(guid).bytes_le)
    renderer.call('Studio_System_GetEventByID', renderer.system, raw, c.byref(desc))
    path, retrieved = c.create_string_buffer(2048), c.c_int()
    renderer.call('Studio_EventDescription_GetPath', desc, path, len(path), c.byref(retrieved))
    count, length, one_shot, snapshot = c.c_int(), c.c_int(), c.c_int(), c.c_int()
    renderer.call('Studio_EventDescription_GetParameterDescriptionCount', desc, c.byref(count))
    renderer.call('Studio_EventDescription_GetLength', desc, c.byref(length))
    renderer.call('Studio_EventDescription_IsOneshot', desc, c.byref(one_shot))
    renderer.call('Studio_EventDescription_IsSnapshot', desc, c.byref(snapshot))
    parameters = {}
    for index in range(count.value):
        parameter = ParameterDescription()
        renderer.call('Studio_EventDescription_GetParameterDescriptionByIndex', desc, index, c.byref(parameter))
        parameters[parameter.name.decode('utf8')] = dict(id=[parameter.id.data1, parameter.id.data2],
            minimum=parameter.minimum, maximum=parameter.maximum, default=parameter.defaultvalue,
            type=parameter.type, flags=parameter.flags)
    return dict(guid=guid, path=path.value.decode('utf8'), parameters=parameters,
                length_ms=length.value, one_shot=bool(one_shot.value), snapshot=bool(snapshot.value))


def audit_parameter_assignment(renderer, guid, values):
    """Ask the shipped FMOD instance, including source invalid/ignored names."""
    desc, instance = c.c_void_p(), c.c_void_p()
    renderer.call('Studio_System_GetEventByID', renderer.system, c.create_string_buffer(uuid.UUID(guid).bytes_le), c.byref(desc))
    renderer.call('Studio_EventDescription_CreateInstance', desc, c.byref(instance))
    assignments = []
    try:
        for name, value in values.items():
            result = renderer.lib.FMOD_Studio_EventInstance_SetParameterByName(instance, name.encode('utf8'), c.c_float(value), 0)
            requested, final = c.c_float(), c.c_float()
            read_result = renderer.lib.FMOD_Studio_EventInstance_GetParameterByName(instance, name.encode('utf8'), c.byref(requested), c.byref(final))
            assignments.append(dict(name=name, value=value, set_result=result, read_result=read_result,
                                    requested=requested.value if not read_result else None))
            if not result and not read_result:
                assert requested.value == value, (guid, name, value, requested.value)
    finally:
        renderer.call('Studio_EventInstance_Release', instance)
    return assignments


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    output = root / 'Samples/ArtDirection/Original/INARI/environment_audio.json'
    catalog_path = root / 'Samples/ArtDirection/Original/INARI/mechanism_catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    for name, digest in catalog['source_sha256'].items():
        assert sha(source / name) == digest, name
    imp = Importer(source, root / 'tmp/art-direction/environment-export')
    levels, profiles, discoveries, hashes = {}, [], [], dict(catalog['source_sha256'])
    for file in sorted([*source.glob('level[0-9]*'), *source.glob('*.assets')]):
        env = UnityPy.load(str(file)); env.typetree_generator = imp.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == file.name}
        headers = []
        for obj in objects.values():
            if obj.type.name != 'MonoBehaviour': continue
            kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
            if kind in TYPES or kind == 'BGMProfile': headers.append((obj, kind))
        discoveries.append(dict(file=file.name, components=[dict(id=o.path_id, type=k) for o, k in headers]))
        hashes[file.name] = sha(file)
        if not headers: continue
        transforms = {o.path_id: o.read_typetree() for o in objects.values() if o.type.name == 'Transform'}
        by_go = {t['m_GameObject']['m_PathID']: tid for tid, t in transforms.items()}
        world = WorldTransforms(transforms)
        entries = {int(e['component_id']): e for e in catalog['scenes'].get(file.name, []) if e['type'] in TYPES}
        assert {o.path_id for o, k in headers if k in TYPES} == set(entries), file.name
        for obj, kind in headers:
            fields, audit = decode(obj)
            if kind == 'BGMProfile':
                dictionary = fields['bgmInfo']
                profiles.append(dict(file=file.name, id=obj.path_id, fields=fields, audit=audit,
                    events={key: guid_string(value['Guid']) for key, value in runtime_dictionary(dictionary['keys'], dictionary['values']).items()}))
                continue
            entry = entries[obj.path_id]
            go = fields['m_GameObject']['m_PathID']
            assert go == int(entry['go'])
            spatial = world.sprite_plane(by_go[go], 16)
            assert spatial == entry['spatial']
            for collider in entry['colliders']:
                assert objects[int(collider['component_id'])].read_typetree() == collider['data']
            dictionary = fields['parameters']
            values = runtime_dictionary(dictionary['keys'], dictionary['values'])
            record = dict(source=entry, fields=fields, audit=audit, parameters=values)
            if kind == 'BGMParameterTrigger': record['event_guid'] = guid_string(fields['Emitter']['Guid'])
            levels.setdefault(file.name, []).append(record)
    assert len(profiles) == 1, profiles
    profile = profiles[0]
    guids = {g for g in profile['events'].values()}
    guids.update(r['event_guid'] for rows in levels.values() for r in rows if 'event_guid' in r)
    guids.discard(str(uuid.UUID(int=0)))
    with tempfile.TemporaryDirectory(prefix='inari-environment-audit-') as temporary:
        renderer = EventRenderer(source, Path(temporary) / 'silent-audit.wav', 17, BANKS)
        try:
            events = {guid: event_metadata(renderer, guid) for guid in sorted(guids)}
            for rows in levels.values():
                for record in rows:
                    kind = record['source']['type']
                    guid = record.get('event_guid') or profile['events']['Ambient' if kind == 'AmbientParameterTrigger' else 'Reverb']
                    record['resolved_event_guid'] = guid
                    record['assignments'] = [] if uuid.UUID(guid).int == 0 else audit_parameter_assignment(renderer, guid, record['parameters'])
        finally: renderer.close()
    for name in ['Plugins/x86_64/fmodstudio.dll', 'Managed/FMODUnity.dll', *(f'StreamingAssets/{bank}.bank' for bank in BANKS)]: hashes[name] = sha(source / name)
    behavior_names = ['Trigger.cs', 'MonoSubject.cs', 'BGMManager.cs', 'BGMProfile.cs', 'GameManager.cs', 'DHUtil.SerializableDictionary/SerializableDictionary.cs', *(name + '.cs' for name in sorted(TYPES))]
    result = dict(schema=1, levels=levels, profile=profile, events=events, scanned_headers=discoveries,
        source_sha256=hashes, behavior_sha256={name: sha(root / 'tmp/art-direction/decompiled' / name) for name in behavior_names},
        input_sha256={catalog_path.relative_to(root).as_posix(): sha(catalog_path)},
        scope='All serialized level/asset files; byte-identical decode roundtrips and shipped FMOD parameter API. Runtime playback not implemented by this catalog.')
    output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf8', newline='\n')
    counts = Counter(r['source']['type'] for rows in levels.values() for r in rows)
    failures = [(s, r['source']['component_id'], a) for s, rows in levels.items() for r in rows for a in r['assignments'] if a['set_result'] or a['read_result']]
    print('ENVIRONMENT_AUDIO_EXPORT', dict(counts), len(events), 'events;', len(failures), 'source parameter failures', flush=True)
    for guid, event in events.items(): print(event['path'], len(event['parameters']), 'parameters', flush=True)
    if failures: print('SOURCE_IGNORED_PARAMETERS', failures, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
