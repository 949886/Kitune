"""Render the checked-in .blend, never a JSON reconstruction.
blender -b --python Tools/render_blend_preview.py -- /absolute/output-directory
Blender-lit inspection images are not Godot gameplay screenshots.
"""
import bpy,sys,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else Path.cwd()
OUTPUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Assets'/'DisappearingPlatform3D.blend'))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.18,.22,.24,1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.8
scene.view_settings.view_transform='Standard';scene.render.image_settings.file_format='PNG'
camera_data=bpy.data.cameras.new('InspectionCamera-noimp');camera=bpy.data.objects.new('InspectionCamera-noimp',camera_data);scene.collection.objects.link(camera)
camera_data.type='ORTHO';camera_data.ortho_scale=220;scene.camera=camera
light_data=bpy.data.lights.new('InspectionKey-noimp','AREA');light=bpy.data.objects.new('InspectionKey-noimp',light_data);scene.collection.objects.link(light);light.location=(-40,-120,140);light_data.energy=250000;light_data.size=130
light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
poses=['sharedassets2_1700','sharedassets2_625','sharedassets2_373']
for index,key in enumerate(poses):
    for obj in scene.objects:
        if obj.type=='MESH':
            obj.hide_render=obj.name not in [key,'sharedassets2_2519','sharedassets6_97']
    for label,position in [('front',Vector((0,-400,-12))),('orbit',Vector((220,-350,120)))]:
        camera.location=position;camera.rotation_euler=(Vector((0,0,-12))-position).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(OUTPUT/f'blend-{index}-{label}.png');bpy.ops.render.render(write_still=True)
print('BLEND_FILE_PREVIEW_PASS',OUTPUT)
