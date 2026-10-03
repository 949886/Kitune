"""Blender-only geometry inspection; alpha thresholded and soft halo omitted.
Run blender -b --python Tools/render_geometry_preview.py -- /path/preview.png
This does not capture or validate Godot rendering.
"""
import bpy,json,math,os,sys
from pathlib import Path
from mathutils import Vector
BASE=str(Path(__file__).resolve().parents[1])
d=json.load(open(BASE+'/Assets/geometry.json'));data=json.load(open(BASE+'/Assets/device.json'));r=data['records']['level7_18316_0']
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=False
scene.render.resolution_x=1500;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.world.color=(.05,.065,.07);scene.view_settings.view_transform='Standard'
materials={}
def mat(c):
 k=tuple(c)
 if k in materials:return materials[k]
 m=bpy.data.materials.new(str(k));m.diffuse_color=(*[v/255 for v in c[:3]],c[3]/255);m.use_nodes=True
 ns=m.node_tree.nodes;ns.clear();out=ns.new('ShaderNodeOutputMaterial');em=ns.new('ShaderNodeEmission');em.inputs[0].default_value=(*[v/255 if v/255<=.04045 else ((v/255+.055)/1.055)**2.4 for v in c[:3]],1);m.node_tree.links.new(em.outputs[0],out.inputs[0]);materials[k]=m;return m
def obj(key,item,origin,angle,order):
 e=d[key];vertices=[];faces=[];colors=[]
 for b in e['boxes']:
  if b[7]<128:continue
  x=b[0]+e['offset'][0];y=-(b[1]+e['offset'][1]);w=b[2];h=b[3];z=order*.25;dep=8 if key.startswith('sharedassets2_') else 2
  start=len(vertices);vertices.extend([(x,y,z),(x+w,y,z),(x+w,y-h,z),(x,y-h,z),(x,y,z-dep),(x+w,y,z-dep),(x+w,y-h,z-dep),(x,y-h,z-dep)])
  for q in [(3,2,1,0),(6,7,4,5),(7,3,0,4),(2,6,5,1),(0,1,5,4),(7,6,2,3)]:faces.append(tuple(start+i for i in q));colors.append(b[4:])
 mesh=bpy.data.meshes.new(key);mesh.from_pydata(vertices,[],faces);mesh.update();ob=bpy.data.objects.new(key,mesh);scene.collection.objects.link(ob)
 slots={}
 for poly,c in zip(mesh.polygons,colors):
  c=tuple(round(c[i]*item['color'][i]) for i in range(4))
  if c not in slots:slots[c]=len(mesh.materials);mesh.materials.append(mat(c))
  poly.material_index=slots[c]
 ob.rotation_euler[1]=angle;p=Vector((item['transform'][4],-item['transform'][5],0));p.rotate(ob.rotation_euler);ob.location=Vector(origin)+p
 return ob
poses=['sharedassets2_1700','sharedassets2_625','sharedassets2_373']
for row,angle in enumerate([0,math.radians(35)]):
 for col,key in enumerate(poses):
  for order,item in enumerate(sorted(r['visuals'],key=lambda x:x['sort'])):
   if item['sprite']=='sharedassets0_446':continue
   k=key if item['go']==r['states'][0]['track']['go'] else item['sprite']
   obj(k,item,((col-1)*210,85-row*165,0),angle,order)
def label(text,x,y,size):
 curve=bpy.data.curves.new('Label','FONT');curve.body=text;curve.size=size;curve.align_x='CENTER';o=bpy.data.objects.new(text,curve);scene.collection.objects.link(o);o.location=(x,y,150);curve.materials.append(mat((210,220,226,255)))
label('CLOSED 3D GEOMETRY  /  FRONT + 35 DEGREE INSPECTION',0,185,12)
for col,t in enumerate(['READY','FOLDING','HIDDEN']):label(t,(col-1)*210,155,11)
label('Blender geometry inspection only. Gameplay projection uses Godot SubViewport.',0,-180,8)
camdata=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',camdata);scene.collection.objects.link(cam);cam.location=(0,10,900);cam.rotation_euler=(0,0,0);camdata.type='ORTHO';camdata.ortho_scale=680;scene.camera=cam
scene.render.filepath=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else str(Path.cwd()/'platform3d-geometry-inspection.png');scene.render.image_settings.file_format='PNG';bpy.ops.render.render(write_still=True)
