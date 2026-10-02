"""Export the actual SpawnManager runtime prefabs, hierarchy and every clip binding.

Default-state names are retained separately from EnemySpawnStamp.aniName: the
shipped stamp names do not match, so its destruction coroutine never completes.
"""
import argparse
import copy
import hashlib
import json
import math
import zlib
from pathlib import Path

from import_inari import Importer, UnityPy, dump
from import_inari_arrow import save_pixels
from portable_device_assets import export_artwork, source_slicing, copy_if_changed
from unity_scene_animation import binding_width, target_paths
from unity_shrine_pose import clip_channels, sample
from unity_scene_spatial import WorldTransforms
from export_device_emitters import export as export_emitters


def export(source):
    root = Path(__file__).resolve().parents[3]
    original = root/'Samples/ArtDirection/Original/INARI'
    package = root/'Samples/INARIMechanisms'
    catalog_path = original/'mechanism_catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf8'))
    for name,digest in catalog['source_sha256'].items():
        assert hashlib.sha256((source/name).read_bytes()).hexdigest() == digest
    staging = root/'tmp/art-direction/arrival-export'
    imp = Importer(source, staging)
    prefabs, references = {}, []
    for scene,entries in catalog['scenes'].items():
        selected = [e for e in entries if e['type'] == 'SpawnManager']
        if not selected: continue
        env = UnityPy.load(str(source/scene));env.typetree_generator = imp.generator
        objects = {o.path_id:o for o in env.objects if o.assets_file.name == scene}
        poses={i:o.read_typetree() for i,o in objects.items() if o.type.name=='Transform'}
        by_go={v['m_GameObject']['m_PathID']:i for i,v in poses.items()}
        world=WorldTransforms(poses)
        for entry in selected:
            obj = objects[int(entry['component_id'])]
            assert obj.read_typetree() == entry['fields']
            member_scales={}
            for phase in entry['fields']['spawnDatas']:
                for ref in phase['EnemyPrefab']:
                    actor=objects[ref['m_PathID']].read_typetree()
                    gfx=world.matrix(by_go[actor['GFXObject']['m_PathID']])
                    assert abs(gfx[1][0])<0.00001 and abs(gfx[2][0])<0.00001
                    root_scale=poses[by_go[actor['m_GameObject']['m_PathID']]]['m_LocalScale']['x']
                    member_scales[str(ref['m_PathID'])]=dict(gfx_scale_x=gfx[0][0],facing=1 if root_scale>=0 else -1)
            for field,kind in [('Stamp','SpawnStamp'),('RifleManRope','SpawnRope')]:
                prefab = imp.pointer(obj.assets_file,entry['fields'][field]).deref()
                identity = (prefab.assets_file.name,prefab.path_id)
                assert kind not in prefabs or prefabs[kind] == identity
                prefabs[kind] = identity
                offset_key = 'stampYOffset' if field == 'Stamp' else 'RifleManRopeYOffset'
                references.append(dict(scene=scene,component=obj.path_id,spawner_go=int(entry['go']),field=field,prefab=identity,offset=entry['fields'][offset_key],member_scales=member_scales))
    audio_path = original/'Audio/battle_events.json'
    audio = json.loads(audio_path.read_text(encoding='utf8'))
    for kind,(filename,root_go) in prefabs.items():
        folder = package/'Assets'/kind;folder.mkdir(parents=True,exist_ok=True)
        env = UnityPy.load(str(source/filename));env.typetree_generator = imp.generator
        objects = {o.path_id:o for o in env.objects if o.assets_file.name==filename}
        gos = {i:o.read_typetree() for i,o in objects.items() if o.type.name=='GameObject'}
        poses = {i:o.read_typetree() for i,o in objects.items() if o.type.name=='Transform'}
        by_go = {v['m_GameObject']['m_PathID']:i for i,v in poses.items()}
        nodes,components,lights,masks = [],{},[],[]
        pending = [(by_go[root_go],None)]
        while pending:
            tid,parent = pending.pop(0);pose=poses[tid];go=pose['m_GameObject']['m_PathID']
            q=pose['m_LocalRotation'];assert q['x']==q['y']==0
            nodes.append(dict(go=go,parent=parent,name=gos[go]['m_Name'],active=bool(gos[go]['m_IsActive']),
                position=[pose['m_LocalPosition'][a] for a in 'xyz'] if parent else [0,0,0],
                rotation=-2*math.atan2(q['z'],q['w']),scale=[pose['m_LocalScale'][a] for a in 'xyz']))
            components[go] = {objects[c['component']['m_PathID']].type.name:objects[c['component']['m_PathID']] for c in gos[go]['m_Component']}
            for child in pose['m_Children']:pending.append((child['m_PathID'],go))
            if 'MonoBehaviour' in components[go]:
                obj=components[go]['MonoBehaviour'];name=obj.parse_monobehaviour_head().m_Script.read().m_ClassName
                if name=='Light2D':lights.append(dict(go=go,fields=obj.read_typetree()))
                else:assert name=='EnemySpawnStamp',name
            if 'SpriteMask' in components[go]:
                obj=components[go]['SpriteMask'];fields=obj.read_typetree()
                masks.append(dict(go=go,fields=fields,sprite=imp.sprite(imp.pointer(obj.assets_file,fields['m_Sprite']))))
        fields = components[root_go]['MonoBehaviour'].read_typetree()
        animator = objects[fields['animator']['m_PathID']].read()
        controller = animator.m_Controller.read_typetree()
        machine = controller['m_Controller']['m_StateMachineArray'][0]['data']
        assert len(machine['m_StateConstantArray'])==1 and not machine['m_AnyStateTransitionConstantArray']
        state=machine['m_StateConstantArray'][machine['m_DefaultState']]['data']
        assert not state['m_TransitionConstantArray'] and not state['m_SpeedParamID']
        clip_pointer=animator.m_Controller.read().m_AnimationClips[0]
        clip=clip_pointer.read_typetree();assert not clip['m_Events'] and not clip['m_MuscleClip']['m_LoopTime']
        channels=clip_channels(clip);paths=target_paths(animator.m_GameObject.path_id,gos,poses,by_go)
        tracks=[];index=0
        for binding in clip['m_ClipBindingConstant']['genericBindings']:
            go=paths[binding['path']];width=binding_width(binding)
            curves=[channels[index+a] for a in range(width)];index+=width
            if binding['typeID']==4:
                prop={1:'position',3:'scale',4:'rotation'}[binding['attribute']]
            elif binding['typeID']==1:
                assert binding['attribute']==zlib.crc32(b'm_IsActive');prop='active'
            elif binding['typeID']==114:
                assert binding['attribute']==zlib.crc32(b'm_Intensity');prop='light_energy'
            elif binding['typeID']==212 and binding['isPPtrCurve']:
                assert binding['customType']==23;prop='sprite'
                mapping=clip['m_ClipBindingConstant']['pptrCurveMapping']
                frames=[[t,imp.sprite(imp.pointer(clip_pointer.deref().assets_file,mapping[round(coeff[3])]))] for t,coeff in curves[0] if t<clip['m_MuscleClip']['m_StopTime']]
            else:
                assert binding['typeID']==212
                prop={zlib.crc32(b'm_Size.y'):'size_y',zlib.crc32(b'm_Color.a'):'alpha'}[binding['attribute']]
            track=dict(go=go,property=prop,curves=curves)
            if prop=='sprite':track['frames']=frames
            tracks.append(track)
        scene=imp.scene(None,asset_file=filename,root_go=root_go)
        visuals=scene['sprites']
        # Runtime uses true parent-local transforms; don't bake the prefab's
        # authored scene position or flatten an animated ancestor into children.
        for visual in visuals:
            visual['transform']=[1,0,0,1,0,0];visual.pop('spatial',None)
            visual['visible']=True
            renderer=components[visual['go']]['SpriteRenderer'].read_typetree()
            visual['mask_interaction']=renderer['m_MaskInteraction']
            visual['renderer_order']=[renderer['m_SortingLayer'],renderer['m_SortingOrder']]
        keys={v['sprite'] for v in visuals if v['sprite']}|{m['sprite'] for m in masks}
        keys.update(s for t in tracks if t['property']=='sprite' for _,s in t['frames'] if s)
        for key in keys:
            image=imp.images[key];info=save_pixels(image,staging,key+'.png')
            imp.sprites[key].update(info,region=[0,0,image.width,image.height])
        slicing=source_slicing(objects,gos,visuals,imp.sprites)
        sprite_info=export_artwork(staging,package,folder,imp.sprites,imp.material_details,visuals,keys,[0,0],slicing)
        event='wave_stamp' if kind=='SpawnStamp' else 'wave_rope'
        for file in audio['groups'][event]:copy_if_changed(original/'Audio'/file,folder/file)
        names=dict(controller['m_TOS'])
        # Independent source-space reference poses catch loss of animated
        # ancestors, Y conversion, scaling and pivot/translation composition.
        samples=[]
        for time in [0.0,0.4,0.8,1.2,clip['m_MuscleClip']['m_StopTime']]:
            sampled_poses=copy.deepcopy(poses)
            sampled_poses[by_go[root_go]]['m_LocalPosition']=dict(x=0,y=0,z=0)
            for track in tracks:
                values=[sample(keys,time) for keys in track['curves']]
                pose=sampled_poses[by_go[track['go']]]
                if track['property'] in ['position','scale']:
                    pose['m_LocalPosition' if track['property']=='position' else 'm_LocalScale']=dict(zip('xyz',values))
                elif track['property']=='rotation':
                    assert values[:2]==[0,0]
                    angle=math.radians(values[2])/2
                    pose['m_LocalRotation']=dict(x=0,y=0,z=math.sin(angle),w=math.cos(angle))
            world=WorldTransforms(sampled_poses)
            samples.append(dict(time=time,transforms={str(n['go']):world.sprite_plane(by_go[n['go']],16)['transform'] for n in nodes}))
        gravity=next(o.read_typetree()['m_Gravity'] for o in UnityPy.load(str(source/'globalgamemanagers')).objects if o.type.name=='Physics2DSettings')
        document=dict(record=dict(go=root_go,fields=fields,animation=dict(children=[n['go'] for n in nodes])), gravity=gravity,
            source_scene=filename,nodes=nodes,lights=lights,masks=masks,sprites=visuals,sprite_info=sprite_info,
            tracks=tracks,source_pose_samples=samples,clip=dict(name=clip['m_Name'],length=clip['m_MuscleClip']['m_StopTime'],speed=state['m_Speed'],
                state_name=names[state['m_NameID']],state_path=names[state['m_FullPathID']],destroy_state=fields['aniName']),
            sorting_group=components[root_go]['SortingGroup'].read_typetree(),audio={event:audio['groups'][event]},
            spawn_references=[r for r in references if r['prefab']==(filename,root_go)],
            source_sha256={**catalog['source_sha256'], **{k:v for k,v in audio['source_sha256'].items() if not k.endswith('.cs')},
                **{name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in {filename,'globalgamemanagers',clip_pointer.deref().assets_file.name,animator.m_Controller.deref().assets_file.name}|{key.rsplit('_',1)[0]+'.assets' for key in keys}}},
            audio_renders={file:audio['renders'][file] for file in audio['groups'][event]},
            input_sha256={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [catalog_path,audio_path]},
            behavior_sha256={**{k:v for k,v in audio['source_sha256'].items() if k.endswith('.cs')},
                **{name:hashlib.sha256((root/'tmp/art-direction/decompiled'/name).read_bytes()).hexdigest() for name in ['EnemySpawnStamp.cs','SpawnManager.cs','TimeManager.cs']}})
        dump(folder/'device.json',document)
        export_emitters(source,kind)
        print(kind,len(visuals),'sprites',len(tracks),'tracks',document['clip'],flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path)
    export(parser.parse_args().source)
