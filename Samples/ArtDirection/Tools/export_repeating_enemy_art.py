"""Export the authored repeating actor and the actual runtime prefab separately.

The prefab differs from the scene override (notably scout/isScout). Existing
calibrated sprite records are retained; new materials use a private namespace.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from import_inari import Importer, UnityPy, dump
from import_inari_arrow import save_pixels
from unity_enemy_bindings import collect
from unity_scene_battle import finish


def export(source):
    root = Path(__file__).resolve().parents[1]
    output = root/'Original/INARI'
    audit_path = root.parent/'INARIMechanisms/Assets/RepeatingSpawner/device.json'
    audit = json.loads(audit_path.read_text(encoding='utf8'))
    profile = audit['profile']
    record = audit['records'][f'{profile["default_scene"]}_{profile["default_component"]}']
    staging = root.parents[1]/'tmp/art-direction/repeating-art-export'
    imp = Importer(source, staging)
    retained = json.loads((output/'sprites.json').read_text(encoding='utf8'))
    imp.sprites = copy.deepcopy(retained)
    materials = json.loads((output/'materials.json').read_text(encoding='utf8'))
    env = UnityPy.load(str(source/record['scene']))
    env.typetree_generator = imp.generator
    objects = {o.path_id:o for o in env.objects if o.assets_file.name == record['scene']}
    component = objects[record['component']]
    assert component.read_typetree() == record['fields']
    assert len(record['members']) == 1, 'Export every new member explicitly before widening the native adapter'
    member = record['members'][0]
    initial = objects[member['source']['stateMachine']['m_PathID']]
    # GetEnemyType maps BombMan to enum 0; resolve from the actual dictionary,
    # not EnemyData.prefab, which the source RespawnEnemy does not read.
    assert initial.parse_monobehaviour_head().m_Script.read().m_ClassName == 'EnemyBombMan'
    table = record['fields']['enemyPrefabDictionary']
    pointer = table['values'][table['keys'].index(0)]
    prefab_go = imp.pointer(component.assets_file, pointer).deref()
    prefab_actor = next(imp.pointer(prefab_go.assets_file, e['component']).deref()
        for e in prefab_go.read_typetree()['m_Component']
        if imp.pointer(prefab_go.assets_file, e['component']).deref().type.name == 'MonoBehaviour'
        and imp.pointer(prefab_go.assets_file, e['component']).deref().parse_monobehaviour_head().m_Script.read().m_ClassName == 'EnemyBombMan')
    result = {'record': record, 'variants': {}, 'audit_sha256':hashlib.sha256(audit_path.read_bytes()).hexdigest()}
    for label, actor in [('initial', initial), ('replacement', prefab_actor)]:
        filename = actor.assets_file.name
        environment = UnityPy.load(str(source/filename)); environment.typetree_generator = imp.generator
        items = {o.path_id:o for o in environment.objects if o.assets_file.name == filename}
        gos = {i:o.read_typetree() for i,o in items.items() if o.type.name == 'GameObject'}
        poses = {i:o.read_typetree() for i,o in items.items() if o.type.name == 'Transform'}
        by_go = {p['m_GameObject']['m_PathID']:i for i,p in poses.items()}
        go = actor.read_typetree()['m_GameObject']['m_PathID']
        bindings, extra = collect(imp, items, gos, poses, by_go, [actor.path_id])
        scene = imp.scene(None, extra_visuals=extra, asset_file=filename, root_go=go)
        assert len(scene['enemies']) == 1
        finish(imp, scene, bindings)
        scene['source_component'] = actor.path_id
        scene['source_go'] = go
        result['variants'][label] = scene
    prefix = 'Repeating/'
    def namespace(value):
        if isinstance(value, list): return [namespace(v) for v in value]
        if not isinstance(value, dict): return value
        item = {k:namespace(v) for k,v in value.items()}
        if isinstance(value.get('material'), str) and value['material']:
            item['material'] = prefix + value['material']
        if value.get('kind') == 'material':
            item['frames'] = [[t, prefix+name if name else name] for t,name in value['frames']]
        return item
    result = namespace(result)
    for name, material in imp.material_details.items():
        materials[prefix+name] = material
    directory = output/'Repeating'; directory.mkdir(exist_ok=True)
    for key,image in imp.images.items():
        if key in retained: continue
        info = save_pixels(image, directory, key+'.png')
        info['path'] = 'Repeating/'+info['path'];info['region'] = [0,0,image.width,image.height]
        imp.sprites[key].update(info)
    imp.sprites.update(retained)
    result['source_sha256'] = {name:hashlib.sha256((source/name).read_bytes()).hexdigest()
        for name in [record['scene'], prefab_go.assets_file.name, 'Managed/Assembly-CSharp.dll']}
    dump(output/'sprites.json', imp.sprites)
    dump(output/'materials.json', materials)
    dump(output/'repeating_enemies.json', result)
    # Generate the playable entry from the audited actor location; presentation
    # choices live in a profile, not coordinates inside gameplay code.
    preview = json.loads((root/'Profiles/native_repeating_preview.json').read_text(encoding='utf8'))
    levels_path = root/'Profiles/levels.json'
    levels = json.loads(levels_path.read_text(encoding='utf8'))
    group = next(p for p in levels if p['id'] == preview['profile'])
    position = result['variants']['initial']['enemies'][0]['position']
    spawn = [a+b for a,b in zip(position, preview['spawn_offset'])]
    entry = dict(id=preview['entry_id'], label=preview['label'], scene_data=record['scene']+'.json',
        spawn=spawn, checkpoints=[spawn], enable_enemies=False, enable_battle=False,
        enable_repeating=True, hidden_sprite_names=['BoxShadow 1'],
        objectives=[dict(name=preview['objective'], position=position, radius=300,
            condition=dict(kind='repeat_count', minimum=preview['minimum_replacements']))])
    previous = next((i for i,e in enumerate(group['practice_entries']) if e.get('id') == preview['entry_id']), None)
    if previous is None: group['practice_entries'].append(entry)
    else: group['practice_entries'][previous] = entry
    levels_path.write_text(json.dumps(levels, ensure_ascii=False, indent=2)+'\n', encoding='utf8', newline='\n')
    print('REPEATING_ART_EXPORT', {k:len(v['sprites']) for k,v in result['variants'].items()}, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
