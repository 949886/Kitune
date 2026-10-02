"""Export serialized MoveSceneObserver destinations and incoming Unity events.

The scene observer is invisible. Its host must supply loading, player input,
out-game storage and persistence; exporting a Timeline call does not port that
Timeline. GUID resolution uses shipped data, never an assumed level order.
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
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    for name, digest in catalog['source_sha256'].items():
        assert hashlib.sha256((source / name).read_bytes()).hexdigest() == digest, name
    build = next(o.read_typetree()['scenes'] for o in UnityPy.load(str(source / 'globalgamemanagers')).objects if o.type.name == 'BuildSettings')
    resources = UnityPy.load(str(source / 'resources.assets'))
    guid_map = json.loads(next(o.read().m_Script for o in resources.objects if o.type.name == 'TextAsset' and o.read().m_Name == 'Eflatun_SceneReference_SceneGuidToPathMap.generated'))
    imp = Importer(source, root / 'tmp/art-direction/scene-observer-export')
    records, hashes = {}, dict(catalog['source_sha256'])
    undecoded = []

    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8', newline='\n')

    def references(value, targets, path=''):
        # Keep the complete serialized call (arguments, mode, call state), not
        # merely a guessed action based on a GameObject name.
        found = []
        if isinstance(value, dict):
            target = value.get('m_Target', {})
            if isinstance(target, dict) and target.get('m_FileID') == 0 and target.get('m_PathID') in targets and 'm_MethodName' in value:
                found.append(dict(path=path, call=value))
            for key, child in value.items():
                found.extend(references(child, targets, f'{path}/{key}'))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                found.extend(references(child, targets, f'{path}/{index}'))
        return found

    for scene, entries in catalog['scenes'].items():
        selected = [e for e in entries if e['type'] == 'MoveSceneObserver']
        env = UnityPy.load(str(source / scene))
        env.typetree_generator = imp.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == scene}
        # Independently inspect all MonoBehaviour headers, including objects
        # with RectTransform or no world transform that the spatial catalog
        # might omit. Fail rather than silently discard an unknown instance.
        discovered = {o.path_id for o in objects.values() if o.type.name == 'MonoBehaviour'
                      and o.parse_monobehaviour_head().m_Script.read().m_ClassName == 'MoveSceneObserver'}
        assert discovered == {int(e['component_id']) for e in selected}, (scene, discovered)
        if not selected:
            continue
        incoming = {int(e['component_id']): [] for e in selected}
        for obj in objects.values():
            if obj.type.name != 'MonoBehaviour':
                continue
            try:
                fields = obj.read_typetree()
            except (EOFError, ValueError) as error:
                # Some middleware layouts cannot be decoded by the generated
                # type tree. Record that gap; incoming-call discovery is not
                # evidence that all Timeline/runtime connections were found.
                undecoded.append(dict(scene=scene, component=obj.path_id,
                                      type=obj.parse_monobehaviour_head().m_Script.read().m_ClassName, error=str(error)))
                continue
            for ref in references(fields, incoming):
                incoming[ref['call']['m_Target']['m_PathID']].append(dict(component=obj.path_id, **ref))
        for entry in selected:
            obj = objects[int(entry['component_id'])]
            assert obj.read_typetree() == entry['fields']
            pointer = imp.pointer(obj.assets_file, entry['fields']['sceneReferenceData'])
            reference = pointer.read_typetree()
            reference_file = pointer.deref().assets_file.name
            hashes[reference_file] = hashlib.sha256((source / reference_file).read_bytes()).hexdigest()
            scene_path = guid_map[reference['SceneReference']['guid']]
            destination = f'level{build.index(scene_path)}'
            key = f'{scene}_{entry["component_id"]}'
            records[key] = dict(source=entry, reference=reference, destination=destination, scene_path=scene_path, incoming_calls=incoming[int(entry['component_id'])])
            write(package / f'Devices/SceneObserver/Presets/{key}.tres',
                  '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
                  '[ext_resource type="Script" path="../ObserverSettings.gd" id="1"]\n\n'
                  '[resource]\nscript = ExtResource("1")\n'
                  f'destination = "{destination}"\nstop_player = {str(bool(entry["fields"]["isPlayerStopped"])).lower()}\n')
    for name in ['globalgamemanagers', 'resources.assets']:
        hashes[name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
    evidence = dict(records=records, source_sha256=hashes, undecoded_incoming_scan=undecoded,
                    discovery_scope='All 29 level files, independently checked MonoBehaviour headers; runtime prefabs excluded.',
                    input_sha256={catalog_path.relative_to(root).as_posix(): hashlib.sha256(catalog_path.read_bytes()).hexdigest()},
                    behavior_sha256={name: hashlib.sha256((root / 'tmp/art-direction/decompiled' / name).read_bytes()).hexdigest() for name in ['MoveSceneObserver.cs', 'Observer.cs', 'GameManager.cs']})
    write(package / 'Assets/SceneObserver/device.json', json.dumps(evidence, ensure_ascii=False, separators=(',', ':')) + '\n')
    for key, record in records.items():
        print(key, '->', record['destination'], 'incoming:', [(r['component'], r['call']['m_MethodName']) for r in record['incoming_calls']], flush=True)
    print('SCENE_OBSERVER_EXPORT', len(records), 'presets; 30 catalog hashes verified', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
