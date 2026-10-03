#!/usr/bin/env python3
"""Author the real editable Blender asset from original art. DEVELOPMENT ONLY.
Run: blender -b --python Tools/build_blend.py
Requires Pillow in Blender's Python only when regenerating from original PNGs.
The checked-in .blend is the runtime model source; this tool is not run in-game.
WARNING: regeneration replaces manual edits in the authored .blend.
"""
import bpy,json,hashlib,math
from pathlib import Path
from PIL import Image
from mathutils import Quaternion
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'DisappearingPlatform'/'Assets'

def rectangles(image):
    rows=[];active={}
    for y in range(image.height):
        runs={};x=0
        while x<image.width:
            color=image.getpixel((x,y));end=x+1
            while end<image.width and image.getpixel((end,y))==color:end+=1
            if color[3]:
                key=(x,end,color);runs[key]=active.pop(key,[x,y,end-x,0,*color]);runs[key][3]+=1
            x=end
        rows.extend(active.values());active=runs
    rows.extend(active.values());return rows

def main():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name != 'Collection':bpy.data.collections.remove(c)
    scene=bpy.context.scene;scene.name='DisappearingPlatform3D'
    scene.unit_settings.system='NONE'
    doc=json.loads((ROOT/'Assets'/'device.json').read_text());record=doc['records']['level7_18316_0']
    ordered=sorted(record['visuals'],key=lambda item:item['sort'])
    poses=bpy.data.collections.new('01 Platform poses (unhide one at a time)');scene.collection.children.link(poses)
    supporting=bpy.data.collections.new('02 Backplate, alarm, soft shadow');scene.collection.children.link(supporting)
    materials={}
    def palette(rgba):
        key=tuple(rgba)
        if key in materials:return materials[key]
        mat=bpy.data.materials.new('RGBA_'+'_'.join(str(round(c*255)) for c in key));mat.use_nodes=True
        linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in key[:3]]
        mat.diffuse_color=(*linear,key[3]);bsdf=mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value=(*linear,1)
        bsdf.inputs['Alpha'].default_value=key[3]
        bsdf.inputs['Roughness'].default_value=1.0
        mat.surface_render_method='DITHERED';materials[key]=mat
        return mat
    manifest={}
    for key,entry in doc['sprites'].items():
        image=Image.open(SOURCE/entry['path']).convert('RGBA');boxes=rectangles(image)
        depth=8.0 if key.startswith('sharedassets2_') else 2.0
        verts=[];faces=[];colors=[]
        for x,y,w,h,r,g,b,a in boxes:
            x+=entry['offset'][0];y=-(y+entry['offset'][1]);start=len(verts)
            # Blender (X,Y,Z) -> Godot (X,Z,-Y); front faces look toward -Y.
            verts.extend([(x,0,y),(x+w,0,y),(x+w,0,y-h),(x,0,y-h),(x,depth,y),(x+w,depth,y),(x+w,depth,y-h),(x,depth,y-h)])
            colors.extend([(r/255,g/255,b/255,a/255)]*8)
            for q in [(3,2,1,0),(6,7,4,5),(7,3,0,4),(2,6,5,1),(0,1,5,4),(7,6,2,3)]:faces.append(tuple(start+i for i in q))
        mesh=bpy.data.meshes.new(key);mesh.from_pydata(verts,[],faces);mesh.update()
        attr=mesh.color_attributes.new(name='Color',type='BYTE_COLOR',domain='POINT')
        for cell,rgba in zip(attr.data,colors):cell.color_srgb=rgba
        slots={}
        for poly in mesh.polygons:
            rgba=colors[poly.vertices[0]]
            if rgba not in slots:
                slots[rgba]=len(mesh.materials);mesh.materials.append(palette(rgba))
            poly.material_index=slots[rgba]
        obj=bpy.data.objects.new(key,mesh)
        is_pose=key not in ['sharedassets2_2519','sharedassets6_97','sharedassets0_446']
        (poses if is_pose else supporting).objects.link(obj)
        item=next((it for it in ordered if it['sprite']==key),next(it for it in ordered if it['go']==record['states'][0]['track']['go']))
        order=ordered.index(item);pose=item['transform'];factor=16/entry['ppu']
        obj.location=(pose[4],-order*.25,-pose[5]);obj.scale=(pose[0]*factor,1,pose[3]*factor)
        obj['source_key']=key;obj['source_artwork']=entry['name'];obj['depth']=depth
        obj['source_png_sha256']=hashlib.sha256((SOURCE/entry['path']).read_bytes()).hexdigest()
        obj['editing_note']='Edit this real mesh; keep object name and local axes. Runtime uses local mesh geometry.'
        obj.hide_set(is_pose and key!='sharedassets2_1700' or key=='sharedassets0_446')
        obj.hide_render=is_pose and key!='sharedassets2_1700' or key=='sharedassets0_446'
        manifest[key]={'vertices':len(verts),'faces':len(faces),'boxes':len(boxes),'depth':depth}
    scene.world.color=(.12,.12,.12)
    scene.view_settings.view_transform='Standard'
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.shading.type='MATERIAL';space.region_3d.view_distance=220
                space.region_3d.view_location=(0,0,-10);space.region_3d.view_rotation=Quaternion((1,0,0),math.pi/2)
                space.region_3d.view_perspective='ORTHO'
    bpy.ops.object.select_all(action='DESELECT')
    ready=bpy.data.objects['sharedassets2_1700'];ready.select_set(True);bpy.context.view_layer.objects.active=ready
    text=bpy.data.texts.new('README - model editing')
    text.write('Editable geometry library: 13 platform poses plus backplate, alarm and soft shadow.\nOnly the ready pose is visible on opening; use Outliner eye icons to select other poses.\nGodot imports ALL objects, including hidden poses. Keep source_key object names stable.\nMeshes are closed solids with editable palette materials; no sprite textures are used.\nRuntime loads this .blend through Godot standard Blender/glTF importer, never geometry.json.\nThe device applies source tint/alpha and animation itself. Local axes: Blender Z up; front is -Y.\n')
    scene['geometry_manifest']=json.dumps(manifest,sort_keys=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Assets'/'DisappearingPlatform3D.blend'),compress=True)
    print('BLEND_MODEL_BUILD_PASS',len(manifest),'meshes')
if __name__=='__main__':main()
