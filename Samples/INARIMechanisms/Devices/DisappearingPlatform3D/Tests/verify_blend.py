"""Run with Blender --background --python Tests/verify_blend.py.
Reloads the real .blend, audits manifold solids and compares all front RGBA cells
against original source artwork. No geometry.json is read or generated.
"""
import bpy,json,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Assets'/'DisappearingPlatform3D.blend'))
doc=json.loads((ROOT/'Assets'/'device.json').read_text())
objects={o.name:o for o in bpy.context.scene.objects if o.type=='MESH'}
assert set(objects)==set(doc['sprites'])
for key,obj in objects.items():
    mesh=obj.data;entry=doc['sprites'][key]
    assert mesh.vertices and mesh.polygons and not mesh.uv_layers
    counts=[0]*len(mesh.edges)
    edge_lookup={tuple(sorted(e.vertices)):e.index for e in mesh.edges}
    actual=Image.new('RGBA',tuple(entry['size']))
    for face in mesh.polygons:
        for edge in face.edge_keys:counts[edge_lookup[tuple(sorted(edge))]]+=1
        if face.normal.y>-.99:continue
        points=[mesh.vertices[i].co for i in face.vertices]
        x=round(min(v.x for v in points)-entry['offset'][0]);y=round(-max(v.z for v in points)-entry['offset'][1])
        w=round(max(v.x for v in points)-min(v.x for v in points));h=round(max(v.z for v in points)-min(v.z for v in points))
        bsdf=mesh.materials[face.material_index].node_tree.nodes.get('Principled BSDF')
        rgb=bsdf.inputs['Base Color'].default_value[:3];alpha=bsdf.inputs['Alpha'].default_value
        rgba=tuple(round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in rgb)+(round(alpha*255),)
        for py in range(y,y+h):
            for px in range(x,x+w):
                assert actual.getpixel((px,py))[3]==0,(key,px,py)
                actual.putpixel((px,py),rgba)
    assert set(counts)=={2},(key,'non-manifold')
    assert max(v.co.y for v in mesh.vertices)-min(v.co.y for v in mesh.vertices)>=1.99
    path=ROOT.parent/'DisappearingPlatform'/'Assets'/entry['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest()==obj['source_png_sha256']
    expected=Image.open(path).convert('RGBA')
    for a,b in zip(actual.getdata(),expected.getdata()):assert a==b or a[3]==b[3]==0,key
print('NATIVE_BLEND_RELOAD_GEOMETRY_PALETTE_PASS: 16 meshes, all closed, all source RGBA fronts exact')
