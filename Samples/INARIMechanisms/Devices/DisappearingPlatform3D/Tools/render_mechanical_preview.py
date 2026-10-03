#!/usr/bin/env python3
"""Render the actual Backplate.blend and Tread.blend together, not reconstructions.

blender -b --python Tools/render_mechanical_preview.py -- /absolute/output
Outputs four explicitly labelled Blender inspection renders and a studio .blend.
These are Blender-lit model inspections, not Godot gameplay screenshots.
"""
import bpy
import math
import sys
import subprocess
import json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else ROOT / 'Inspection'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'Assets' / 'Backplate.blend'))
with bpy.data.libraries.load(str(ROOT / 'Assets' / 'Tread.blend'), link=False) as (source, target):
    target.objects = source.objects
for obj in target.objects:
    bpy.context.scene.collection.objects.link(obj)

# Check actual evaluated geometry throughout the native animation, not metadata
# or object bounding boxes. Bearing/shaft mating surfaces are intentionally omitted.
clearance = {'frames': [], 'intersection_pairs': 0,
             'scope': 'Gears and tread/deck meshes versus recessed frame, backing and face mounting bolts'}
moving_names = ['GearLeft', 'GearRight', 'TreadBody', 'TreadEdgeRails',
                'TreadInset', 'TreadGripRibs', 'TreadUndersidePanel', 'TreadUndersideRibs']
fixed_names = ['FrameBody', 'RecessedBacking', 'MountingBolts']
for frame in range(13):
    bpy.context.scene.frame_set(frame)
    graph = bpy.context.evaluated_depsgraph_get()
    trees = {}
    for name in moving_names + fixed_names:
        obj = bpy.data.objects[name].evaluated_get(graph)
        evaluated = obj.to_mesh()
        vertices = [obj.matrix_world @ v.co for v in evaluated.vertices]
        polygons = [list(p.vertices) for p in evaluated.polygons]
        trees[name] = BVHTree.FromPolygons(vertices, polygons, epsilon=1e-6)
        obj.to_mesh_clear()
    hits = []
    for moving in moving_names:
        for fixed in fixed_names:
            overlap = trees[moving].overlap(trees[fixed])
            if overlap:
                hits.append({'moving': moving, 'fixed': fixed, 'triangles': len(overlap)})
    clearance['frames'].append({'frame': frame, 'degrees': frame*7.5, 'intersections': hits})
    clearance['intersection_pairs'] += len(hits)
(OUT / 'mechanical-sweep-clearance.json').write_text(json.dumps(clearance, indent=2))
assert clearance['intersection_pairs'] == 0, clearance

scene = bpy.context.scene
scene.name = 'Blender - mechanical asset inspection'
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = False
scene.render.threads_mode = 'FIXED'
scene.render.threads = 8
scene.render.resolution_x = 1400
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.world = bpy.data.worlds.new('InspectionStudio')
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get('Background')
background.inputs[0].default_value = (.055, .075, .078, 1)
background.inputs[1].default_value = .45


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


for name, xyz, energy, size, color in [
    ('StudioKey-noimp', (-100, -110, 180), 1300000, 150, (1, .94, .85)),
    ('StudioFill-noimp', (160, -190, 60), 950000, 170, (.73, .87, 1)),
    ('StudioRim-noimp', (80, 95, 125), 1700000, 120, (.8, 1, .95)),
]:
    data = bpy.data.lights.new(name, 'AREA')
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = xyz
    data.energy, data.size, data.color = energy, size, color
    point_at(obj, (0, 0, -5))

data = bpy.data.cameras.new('InspectionCamera-noimp')
camera = bpy.data.objects.new('InspectionCamera-noimp', data)
scene.collection.objects.link(camera)
data.type = 'ORTHO'
data.ortho_scale = 216
data.clip_start, data.clip_end = .1, 2000
scene.camera = camera

text_mat = bpy.data.materials.new('InspectionLabel-noimp')
text_mat.use_nodes = True
nodes = text_mat.node_tree.nodes
nodes.clear()
emission = nodes.new('ShaderNodeEmission')
emission.inputs[0].default_value = (.65, .82, .8, 1)
out = nodes.new('ShaderNodeOutputMaterial')
text_mat.node_tree.links.new(emission.outputs[0], out.inputs['Surface'])


def label(name, body, x, y, size):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.size = size
    curve.space_character = 1.15
    curve.materials.append(text_mat)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.parent = camera
    obj.location = (x, y, -100)
    return obj


header = label('RenderLabel-noimp', '', -99, 56, 4.2)
footer = label('RenderFootnote-noimp', '', -99, -59, 2.3)
hinge = bpy.data.objects['TreadHinge']
backplate = bpy.data.objects['BackplateRoot']
originals = {o.name: o.location.copy() for o in scene.objects if o.type == 'MESH'}
views = [
    ('blender-ready-front', '01  READY / FRONT', (0, -420, -4), (0, 0, -4), 0),
    ('blender-ready-angled', '02  READY / THREE-QUARTER', (195, -315, 166), (0, -6, -2), 0),
    ('blender-folded-front', '03  FOLDED / FRONT', (0, -420, -4), (0, 0, -4), 12),
    ('blender-exploded-angled', '04  EXPLODED / TWO EDITABLE ASSETS', (205, -325, 182), (0, -13, -5), 0),
]
for slug, title, position, target, frame in views:
    requested = [arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--only=')]
    if requested and slug not in requested:
        continue
    data.ortho_scale = 260 if 'exploded' in slug else 216
    header.location.x = footer.location.x = -data.ortho_scale / 2 + 9
    header.location.y = data.ortho_scale * 900 / 1400 / 2 - 13
    footer.location.y = -data.ortho_scale * 900 / 1400 / 2 + 10
    scene.frame_set(frame)
    hinge.location = (0, 0, 0)
    backplate.location = (0, 0, 0)
    for name, location in originals.items():
        bpy.data.objects[name].location = location
    if 'exploded' in slug:
        backplate.location.y = 15
        hinge.location.y = -32
        hinge.rotation_euler.x = math.radians(22)
        for side, sign in [('L', -1), ('R', 1)]:
            bpy.data.objects['GearLeft' if side == 'L' else 'GearRight'].location.x += sign * 22
            for prefix in ['GearHub_', 'GearHubCap_']:
                bpy.data.objects[prefix + side].location.x += sign * 22
        footer.data.body = 'BLENDER INSPECTION  /  SPACING SEPARATED FOR CLARITY  /  16-TOOTH SOLID GEARS'
    else:
        footer.data.body = 'BLENDER INSPECTION  /  NATIVE .BLEND GEOMETRY  /  96-WIDE TREAD  /  SINGLE X-AXIS HINGE'
    header.data.body = title
    camera.location = position
    point_at(camera, target)
    scene.render.filepath = str(OUT / (slug + '.png'))
    bpy.ops.render.render(write_still=True)

scene.frame_set(0)
hinge.location = (0, 0, 0)
backplate.location = (0, 0, 0)
for name, location in originals.items():
    bpy.data.objects[name].location = location
camera.location = (195, -315, 166)
point_at(camera, (0, -6, -2))
data.ortho_scale = 216
header.location = (-99, 56, -100)
footer.location = (-99, -59, -100)
header.data.body = 'BLENDER / MECHANICAL ASSET INSPECTION'
footer.data.body = 'TWO IMPORTED .BLEND ASSETS / ANIMATE TREADHINGE FRAMES 0-12 / 60 FPS'
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'BlenderInspection.blend'), compress=True)
# An unlabelled, transparent, true orthographic 1 pixel/unit projection is useful
# for comparing footprint to the original sprite. This is still a Blender render.
scene.render.resolution_x = 192
scene.render.resolution_y = 128
scene.render.film_transparent = True
scene.render.image_settings.color_mode = 'RGBA'
data.ortho_scale = 192
camera.location = (0, -420, 0)
point_at(camera, (0, 0, 0))
header.hide_render = footer.hide_render = True
for label, frame in [('ready', 0), ('folded', 12)]:
    scene.frame_set(frame)
    scene.render.filepath = str(OUT / ('blender-footprint-' + label + '-192x128.png'))
    bpy.ops.render.render(write_still=True)
if '--footprint-sequence' in sys.argv:
    for frame in range(13):
        scene.frame_set(frame)
        scene.render.filepath = str(OUT / ('footprint-step-%02d.png' % frame))
        bpy.ops.render.render(write_still=True)
scene.render.film_transparent = False
scene.render.image_settings.color_mode = 'RGB'
data.ortho_scale = 216
camera.location = (195, -315, 166)
point_at(camera, (0, -6, -2))
header.hide_render = footer.hide_render = False
if '--motion' in sys.argv:
    # Render thirteen distinct native hinge positions, then play them forward/back.
    # The inspection video is slowed down; Godot preserves the source's 0.2 s fold.
    motion_dir = OUT / 'motion-frames'
    motion_dir.mkdir(exist_ok=True)
    scene.render.resolution_x = 840
    scene.render.resolution_y = 540
    scene.cycles.samples = 16
    header.data.body = 'BLENDER / SINGLE-HINGE MOTION'
    footer.data.body = 'SLOWED INSPECTION / SAME TREAD + SHAFT + TWO SOLID GEARS / NATIVE FOLD ACTION'
    for frame in range(13):
        scene.frame_set(frame)
        scene.render.filepath = str(motion_dir / ('frame%03d.png' % frame))
        bpy.ops.render.render(write_still=True)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '10',
                    '-i', str(motion_dir / 'frame%03d.png'), '-filter_complex',
                    '[0:v]split[f][b];[b]reverse[b];[f][b]concat=n=2:v=1:a=0,tpad=start_duration=0.5:stop_duration=0.5:start_mode=clone:stop_mode=clone[v]',
                    '-map', '[v]', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart', str(OUT / 'blender-hinge-motion-slowed.mp4')], check=True)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-i', str(OUT / 'blender-hinge-motion-slowed.mp4'), '-filter_complex',
                    '[0:v]fps=10,scale=700:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse',
                    '-loop', '0', str(OUT / 'blender-hinge-motion-slowed.gif')], check=True)
print('MECHANICAL_RENDER_PASS', OUT)
