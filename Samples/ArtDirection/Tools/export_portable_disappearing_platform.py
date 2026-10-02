"""Export DisappearTiles groups, original sprite clocks and collision polygons.

Read-only Unity input. Each four-connected tile group becomes an independent
Godot scene instance. The runtime folder has no references outside itself.
"""
import argparse
import hashlib
import json
import zlib
from pathlib import Path
from import_inari import Importer, UnityPy, multiply, rgba
from unity_parameter_triggers import decode
from unity_scene_spatial import WorldTransforms
from unity_scene_animation import animator_tracks, target_paths, streamed_curves
from import_inari_event_audio import export as export_audio


def connected_groups(cells):
    # Unity BoundsInt enumerates X fastest, then Y. Preserve that first cell for
    # the original x+y animator ordering, instead of relying on asset table order.
    pending = set(cells)
    groups = []
    for first in sorted(cells, key=lambda p: (p[2], p[1], p[0])):
        if first not in pending:
            continue
        group, stack = [], [first]
        while stack:
            cell = stack.pop()
            if cell not in pending:
                continue
            pending.remove(cell)
            group.append(cell)
            x, y, z = cell
            stack.extend([(x, y+1, z), (x, y-1, z), (x+1, y, z), (x-1, y, z)])
        groups.append(group)
    return sorted(groups, key=lambda g: g[0][0] + g[0][1])


def export(source):
    root = Path(__file__).resolve().parents[3]
    folder = root / 'Samples/INARIMechanisms/Devices/DisappearingPlatform'
    assets = folder / 'Assets'
    assets.mkdir(parents=True, exist_ok=True)
    imp = Importer(source, root / 'tmp/art-direction/disappear-review/export')
    records, sources, headers = {}, {}, []
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for path in sorted([*source.glob('level[0-9]*'), *source.glob('*.assets')]):
        env = UnityPy.load(str(path)); env.typetree_generator = imp.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == path.name}
        found = [o for o in objects.values() if o.type.name == 'MonoBehaviour'
                 and o.parse_monobehaviour_head().m_Script.read().m_ClassName == 'DisappearTiles']
        headers.append(dict(file=path.name, ids=[o.path_id for o in found]))
        sources[path.name] = sha(path)
        if not found:
            continue
        gos = {k:o.read_typetree() for k,o in objects.items() if o.type.name == 'GameObject'}
        poses = {k:o.read_typetree() for k,o in objects.items() if o.type.name == 'Transform'}
        by_go = {v['m_GameObject']['m_PathID']:k for k,v in poses.items()}
        world = WorldTransforms(poses)
        for obj in found:
            fields, audit = decode(obj, {'DisappearTiles'})
            tilemap = objects[fields['tilemap']['m_PathID']].read_typetree()
            cells = [tuple(p[a] for a in 'xyz') for p, _ in tilemap['m_Tiles']]
            groups = connected_groups(cells)
            assert len(groups) == len(fields['animators'])
            assert len({g[0][0]+g[0][1] for g in groups}) == len(groups)
            tile_pose = world.sprite_plane(by_go[tilemap['m_GameObject']['m_PathID']], 16)['transform']
            composite = objects[fields['coll']['m_PathID']].read_typetree()
            polygons = composite['m_CompositePaths']['m_Paths']
            assert len(polygons) == len(groups)
            for rank, group in enumerate(groups):
                animator = objects[fields['animators'][rank]['m_PathID']]
                a = animator.read(); c = a.m_Controller.read_typetree()
                paths = target_paths(a.m_GameObject.path_id, gos, poses, by_go)
                machine = c['m_Controller']['m_StateMachineArray'][0]['data']
                names = dict(c['m_TOS'])
                assert machine['m_DefaultState'] == 0 and not machine['m_AnyStateTransitionConstantArray']
                states = []
                for index, wrapped in enumerate(machine['m_StateConstantArray']):
                    state = wrapped['data']
                    tracks = animator_tracks(imp, animator, paths, poses, by_go, selected_state=index)
                    assert len(tracks) == 1 and tracks[0]['kind'] == 'sprite'
                    assert tracks[0]['speed'] > 0
                    leaves = [n['data'] for t in state['m_BlendTreeConstantArray'] for n in t['data']['m_NodeArray'] if not n['data']['m_ChildIndices']]
                    assert len(leaves) == 1
                    clip = a.m_Controller.read().m_AnimationClips[leaves[0]['m_ClipID']].read_typetree()
                    bindings = clip['m_ClipBindingConstant']['genericBindings']
                    assert len(bindings) == 2 and bindings[0]['attribute'] == zlib.crc32(b'm_Color.a')
                    assert bindings[0]['typeID'] == 212 and bindings[0]['path'] == zlib.crc32(b'Emission')
                    alpha = dict(go=paths[bindings[0]['path']], keys=streamed_curves(clip)[0])
                    tracks[0].pop('unsupported_bindings')  # Handled explicitly by alpha below.
                    states.append(dict(name=names[state['m_NameID']], track=tracks[0], alpha=alpha, transitions=state['m_TransitionConstantArray']))
                assert [s['name'] for s in states] == ['trap_idle','trap_active','trap_active_idle','trap_recover']
                # Match the baked composite polygon to this contiguous cell group.
                lo = [min(p[i] for p in group) for i in range(2)]
                hi = [max(p[i] for p in group)+1 for i in range(2)]
                polygon = next(p for p in polygons if abs(min(v['x'] for v in p)-lo[0]) < .001
                               and abs(min(v['y'] for v in p)-lo[1]) < .001)
                assert abs(max(v['x'] for v in polygon)-hi[0]) < .001
                origin = multiply(tile_pose, [1,0,0,1,(lo[0]+hi[0])*8,-hi[1]*16])[4:]
                local_poly = []
                for v in polygon:
                    xy = multiply(tile_pose,[1,0,0,1,v['x']*16,-v['y']*16])[4:]
                    local_poly.append([xy[i]-origin[i] for i in range(2)])
                visuals = []
                for gid in paths.values():
                    for comp in gos[gid]['m_Component']:
                        renderer = objects[comp['component']['m_PathID']]
                        if renderer.type.name != 'SpriteRenderer': continue
                        d = renderer.read_typetree(); ptr = imp.pointer(renderer.assets_file,d['m_Sprite'])
                        key = imp.sprite(ptr)
                        pose = world.sprite_plane(by_go[gid],16)['transform']
                        pose[4:] = [pose[4+i]-origin[i] for i in range(2)]
                        # Sprite pixels and tint are native. The package deliberately
                        # does not depend on Unity URP lighting or the host's shaders.
                        visuals.append(dict(go=gid, sprite=key, transform=pose, color=rgba(d['m_Color']),
                                            sort=[d['m_SortingLayer'], d['m_SortingOrder']],
                                            flip=[d['m_FlipX'],d['m_FlipY']], visible=bool(d['m_Enabled'] and gos[gid]['m_IsActive'])))
                key = f'{path.name}_{obj.path_id}_{rank}'
                records[key] = dict(source_scene=path.name, component=obj.path_id, rank=rank,
                                    fields=fields, audit=audit, cells=group, polygon=local_poly,
                                    origin=origin, states=states, visuals=visuals)
                presets = folder/'Presets'; presets.mkdir(exist_ok=True)
                (presets/(key+'.tres')).write_text('[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Script" path="../PlatformSettings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\nsource_key = "'+key+'"\n',encoding='utf8')
    for key, info in imp.sprites.items():
        image = imp.images[key]; image.save(assets/(key+'.png'))
        info.update(path=key+'.png', pixel_sha256=hashlib.sha256(image.tobytes()).hexdigest())
    # A real source event, rendered with its authored mixing/timing.
    export_audio(source, root/'tmp/art-direction/decompiled', assets, 1, 'Object',
                 {'TrapPlatform':'activate'}, 'disappearing_platform', 'DisappearTiles.cs',
                 banks=('Master','Master.strings','SFX_Object','Snapshot'))
    audio = json.loads((assets/'disappearing_platform_events.json').read_text(encoding='utf8'))
    document = dict(records=records, sprites=imp.sprites, audio=audio, scanned_headers=headers,
                    source_sha256=sources, behavior_sha256=sha(root/'tmp/art-direction/decompiled/DisappearTiles.cs'))
    (assets/'device.json').write_text(json.dumps(document,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf8')
    print('DISAPPEARING_PLATFORM_EXPORT_PASS',len(records),'groups',len(imp.sprites),'sprites',flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('source',type=Path)
    export(parser.parse_args().source)
