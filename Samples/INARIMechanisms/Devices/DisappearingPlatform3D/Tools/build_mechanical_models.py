#!/usr/bin/env python3
"""Author two editable mechanical assets, without reading the old frame library.

Run with Blender 4.3+: blender -b --python Tools/build_mechanical_models.py
Optional: append -- /absolute/inspection/output for a validation JSON and GLBs.
Regeneration replaces manual changes to Backplate.blend and Tread.blend.
Units match the original 2D artwork; Blender Z up / -Y forward becomes
Godot Y up / +Z forward. Native .blend files are the runtime model sources.
"""
from pathlib import Path
import bpy
import bmesh
import hashlib
import json
import math
import sys
from PIL import Image
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Assets'
SOURCE = ROOT.parent / 'DisappearingPlatform' / 'Assets'
OUT = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else ROOT / 'Inspection'
OUT.mkdir(parents=True, exist_ok=True)
PALETTE = {
    'Frame_Charcoal': ('000000', .15, .55),
    'Frame_DeepShadow': ('000000', .15, .55),
    'Hardware_Charcoal': ('21201e', .30, .40),
    'Gear_RootShadow': ('1a1919', .30, .45),
    'Gear_ToothCrest': ('464442', .35, .40),
    'Gear_ToothFlank': ('292726', .30, .45),
    'Tread_DeepTeal': ('17302c', .28, .40),
    'Tread_InsetTeal': ('1a1f1f', .20, .50),
    'Edges_BrushedSteel': ('4b5f5c', .35, .38),
    'Gears_Gunmetal': ('434343', .35, .40),
    'Bolts_PaleSteel': ('6b6b6b', .35, .38),
    'Warning_MutedBrass': ('a39052', .30, .40),
    'Alarm_Red': ('d33c34', .25, .27),
}
MATS = {}
PARTS = []


def linear(v):
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4


def material(name):
    if name in MATS:
        return MATS[name]
    rgb, metal, rough = PALETTE[name]
    srgb = tuple(int(rgb[k:k + 2], 16) / 255 for k in (0, 2, 4)) if isinstance(rgb, str) else rgb
    color = tuple(linear(value) for value in srgb)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    if name == 'Alarm_Red':
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = .7
    MATS[name] = mat
    return mat


def source_material(prefix, rgb, modulation=1.0):
    """Baked vertex-face palette, never a texture or an alpha-hidden RGB sample."""
    name = prefix + '_' + ''.join('%02x' % value for value in rgb)
    if name not in PALETTE:
        PALETTE[name] = (tuple(value / 255 * modulation for value in rgb), .25, .45)
    return name


def new_scene(name):
    global MATS, PARTS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    MATS, PARTS = {}, []
    scene = bpy.context.scene
    scene.name = name
    scene.unit_settings.system = 'NONE'
    scene.render.fps = 60
    scene.frame_start = 0
    scene.frame_end = 12
    scene.view_settings.view_transform = 'AgX'
    root = bpy.data.objects.new('TreadHinge' if name == 'Tread' else 'BackplateRoot', None)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = 14
    scene.collection.objects.link(root)
    root['coordinate_contract'] = 'Blender X right, Z up, -Y front -> Godot X right, Y up, +Z front'
    root['source_hinge_pixel'] = [61, 23] if name == 'Tread' else [82, 42]
    root['ready_rail_top'] = 4.0
    root['assembly'] = name
    return root


def finish(obj, name, mat, parent, bevel=0):
    obj.name = name
    obj.data.name = name + '_Mesh'
    obj.data.materials.clear()
    obj.data.materials.append(material(mat))
    obj.parent = parent
    if bevel:
        mod = obj.modifiers.new('Editable machined edge bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.affect = 'EDGES'
        mod.limit_method = 'ANGLE'
        mod.harden_normals = True
        normal = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        normal.weight = 30
        for face in obj.data.polygons:
            face.use_smooth = True
    PARTS.append(obj)
    return obj


def box(name, size, center, mat, parent, bevel=.35):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, parent, bevel)


def cylinder(name, radius, depth, center, mat, parent, axis='X', vertices=32, bevel=.2):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=center)
    obj = bpy.context.object
    obj.rotation_euler = (0, math.pi / 2, 0) if axis == 'X' else (math.pi / 2, 0, 0) if axis == 'Y' else (0, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, name, mat, parent, bevel)


def ring(name, outer, inner, y0, y1, mat, parent, bevel=.35):
    """Closed rectangular annulus with a real through-opening, in the X/Z plane."""
    def contour(bounds, y):
        x0, x1, z0, z1 = bounds
        return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    vertices = contour(outer, y0) + contour(inner, y0) + contour(outer, y1) + contour(inner, y1)
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces += [(i, j, j + 4, i + 4), (i + 8, i + 12, j + 12, j + 8),
                  (i, i + 8, j + 8, j), (i + 4, j + 4, j + 12, i + 12)]
    return mesh(name, vertices, faces, mat, parent, bevel)


def mesh(name, vertices, faces, mat, parent, bevel=.2):
    data = bpy.data.meshes.new(name + '_Mesh')
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return finish(obj, name, mat, parent, bevel)


def annular_gear(name, x, parent):
    """One manifold 16-tooth wheel with a bore, front/back faces and tooth flanks.

    Six outline samples per tooth preserve a flat tooth crest and sloped flanks.
    The toothed annulus is authored as connected quads, not disconnected boxes.
    """
    teeth, width, root_radius, tip_radius, bore = 16, 8.0, 101/6, 21.0, 3.5
    outline = []
    for i in range(teeth):
        for phase, radius in [(0, root_radius), (.15, root_radius), (.30, tip_radius),
                              (.60, tip_radius), (.75, root_radius), (.95, root_radius)]:
            # A crest endpoint is cardinal, giving actual X-axis-view height 42
            # rather than merely a nominal 42-unit circumscribed diameter.
            a = (i + phase - .30) * 2 * math.pi / teeth
            outline.append((a, radius))
    n = len(outline)
    vertices = []
    for dx, inner in [(-width / 2, False), (width / 2, False),
                      (-width / 2, True), (width / 2, True)]:
        for a, radius in outline:
            r = bore if inner else radius
            vertices.append((dx, math.cos(a) * r, math.sin(a) * r))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.extend([(i, j, n + j, n + i), (i, 2*n+i, 2*n+j, j),
                      (n+i, n+j, 3*n+j, 3*n+i), (2*n+i, 3*n+i, 3*n+j, 2*n+j)])
    obj = mesh(name, vertices, faces, 'Hardware_Charcoal', parent, .08)
    for palette in ['Gear_RootShadow', 'Gear_ToothCrest', 'Gear_ToothFlank']:
        obj.data.materials.append(material(palette))
    for i in range(n):
        ra, rb = outline[i][1], outline[(i+1)%n][1]
        obj.data.polygons[4*i].material_index = 2 if ra == rb == tip_radius else 1 if ra == rb == root_radius else 3
    obj.location.x = x
    obj['gear_teeth'] = teeth
    obj['gear_axis'] = 'X'
    obj['gear_outer_diameter'] = tip_radius * 2
    obj['gear_root_diameter'] = root_radius * 2
    obj['gear_axial_width'] = width
    obj['gear_bore_diameter'] = bore * 2
    return obj


def recessed_tread(parent):
    """A single closed plank, with an actual shallow pocket for the inset panel."""
    def rectangle(x0, x1, y0, y1, z):
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    vertices = (rectangle(-48, 48, -57, -2, -3.6) + rectangle(-48, 48, -57, -2, 4)
                + rectangle(-43, 43, -54.6, -6, 4) + rectangle(-43, 43, -54.6, -6, 3.75))
    faces = [(3, 2, 1, 0), (12, 13, 14, 15)]
    for i in range(4):
        j = (i + 1) % 4
        faces.extend([(i, j, j+4, i+4), (i+4, j+4, j+8, i+8), (i+8, j+8, j+12, i+12)])
    return mesh('TreadBody', vertices, faces, 'Tread_DeepTeal', parent, .18)


def source_front_lip(parent):
    """One closed 2-unit-deep rail; front faces carry the nine opaque source rows.

    A shared-vertex surface grid keeps each groove/highlight editable and manifold.
    Only READY pixels x13..108/y19..27 are used. Transparent pixels at the two
    bottom corners are omitted; transparent grey/teal shapes are never modeled.
    """
    image = Image.open(SOURCE / 'sharedassets2_1700.png').convert('RGBA')
    pixels = {(x, y): image.getpixel((x, y))[:3] for y in range(19, 28) for x in range(13, 109)
              if image.getpixel((x, y))[3] > 128}
    vertices, indices, faces, palettes = [], {}, [], []
    def vertex(x, depth, y):
        key = (x, depth, y)
        if key not in indices:
            indices[key] = len(vertices)
            vertices.append((x-61, depth, 23-y))
        return indices[key]
    for (x, y), rgb in pixels.items():
        front = [vertex(xx, -59, yy) for xx, yy in [(x,y),(x+1,y),(x+1,y+1),(x,y+1)]]
        back = [vertex(xx, -57, yy) for xx, yy in [(x,y),(x+1,y),(x+1,y+1),(x,y+1)]]
        faces.extend([tuple(front), tuple(reversed(back))])
        palettes.extend([source_material('Rail_Source', rgb)] * 2)
        for neighbor, a, b in [((x,y-1),0,1), ((x+1,y),1,2), ((x,y+1),2,3), ((x-1,y),3,0)]:
            if neighbor not in pixels:
                faces.append((front[a], back[a], back[b], front[b]))
                palettes.append(source_material('Rail_Source', rgb))
    obj = mesh('TreadEdgeRails', vertices, faces, 'Tread_DeepTeal', parent, 0)
    slots = {'Tread_DeepTeal': 0}
    for name in palettes:
        if name not in slots:
            slots[name] = len(obj.data.materials)
            obj.data.materials.append(material(name))
    for face, name in zip(obj.data.polygons, palettes):
        face.material_index = slots[name]
    obj['source_profile'] = 'sharedassets2_1700.png; alpha>128 x13..108 y19..27; exact opaque RGB faces'
    obj['ready_bounds_xz'] = [-48, 48, -5, 4]
    obj['opaque_source_pixels'] = len(pixels)
    return obj


def traced_backplate(parent):
    """Trace only the static source silhouette, then create a real recessed solid.

    The original frame has characteristic diagonal corners and wider side ears.
    Alpha is used once during authoring; no texture is packed or used at runtime.
    """
    image = Image.open(SOURCE / 'sharedassets2_2519.png').convert('RGBA')
    pixels = image.load()
    mask = {(x, y) for y in range(image.height) for x in range(image.width) if pixels[x, y][3] > 128}
    # Ignore isolated antialiasing fragments: trace the largest connected region.
    regions = []
    while mask:
        seed = mask.pop()
        region, pending = {seed}, [seed]
        while pending:
            x, y = pending.pop()
            for neighbor in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)]:
                if neighbor in mask:
                    mask.remove(neighbor)
                    region.add(neighbor)
                    pending.append(neighbor)
        regions.append(region)
    mask = max(regions, key=len)
    edges = {}
    for x, y in mask:
        for neighbor, a, b in [((x, y-1), (x, y), (x+1, y)), ((x+1, y), (x+1, y), (x+1, y+1)),
                               ((x, y+1), (x+1, y+1), (x, y+1)), ((x-1, y), (x, y+1), (x, y))]:
            if neighbor not in mask:
                edges.setdefault(a, []).append(b)
    loops = []
    while edges:
        start = next(iter(edges))
        points, current = [start], start
        while True:
            following = edges[current].pop()
            if not edges[current]:
                del edges[current]
            current = following
            if current == start:
                break
            points.append(current)
        loops.append(points)
    area = lambda points: abs(sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(points, points[1:]+points[:1])))
    outline = max(loops, key=area)
    # Drop redundant collinear points but keep every authored step and diagonal.
    outline = [b for a, b, c in zip(outline[-1:]+outline[:-1], outline, outline[1:]+outline[:1])
               if (b[0]-a[0])*(c[1]-b[1]) != (b[1]-a[1])*(c[0]-b[0])]
    n = len(outline)
    vertices = [(x-82, depth, 42-y) for depth in [4, 28] for x, y in outline]
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, 2*n))]
    faces.extend((i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n))
    body = mesh('FrameBody', vertices, faces, 'Frame_Charcoal', parent, 0)
    body['source_profile'] = 'sharedassets2_2519.png; largest alpha>128 region; original stepped contour'
    body['source_profile_vertices'] = n
    # A deep pocket leaves the back connected and watertight; the separate dark
    # backing sits on its floor rather than covering a nonexistent opening.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 10, -1.5))
    cutter = bpy.context.object
    cutter.name = 'Authoring pocket cutter'
    cutter.dimensions = (120, 30, 59)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = body.modifiers.new('Recessed backing pocket', 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.object = cutter
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    # The tread's underside stays below Y=5 when folded. Relieve the lower lip
    # to Y=7.5, retaining the opaque silhouette and solid structural backing.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 1, -45))
    cutter = bpy.context.object
    cutter.dimensions = (99, 13, 30)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = body.modifiers.new('Folded tread lower-lip clearance', 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.object = cutter
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    body['folded_tread_clearance'] = 'Lower frame lip recessed to Y=7.5; folded tread underside Y<=5. Gear pocket floor Y=25 clears radius21.'
    finish(body, 'FrameBody', 'Frame_Charcoal', parent, .18)
    return body


def source_frame_details(parent):
    """Original dim compartment marks, authored as closed raised rectangular runs.

    Equal-color source pixels are greedily merged into rectangular struts, then
    joined into one mesh. No per-pixel nodes, raster planes, or image materials.
    Marks in the pocket sit on its floor; all front-view coordinates are exact.
    """
    image = Image.open(SOURCE / 'sharedassets2_2519.png').convert('RGBA')
    runs = {}
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, alpha = image.getpixel((x, y))
            if alpha <= 128 or not (r or g or b):
                continue
            xx, zz = x+.5-82, 42-y-.5
            depth = 24.55 if abs(xx) < 60 and -31 < zz < 28 else 7.25 if abs(xx) < 49.5 and zz < -30 else 3.75
            runs[(x,y)] = ((r,g,b), depth)
    struts = []
    while runs:
        x, y = min(runs, key=lambda p: (p[1], p[0]))
        key = runs[(x,y)]
        width = 1
        while runs.get((x+width,y)) == key:
            width += 1
        height = 1
        while all(runs.get((xx,y+height)) == key for xx in range(x,x+width)):
            height += 1
        for yy in range(y,y+height):
            for xx in range(x,x+width):
                del runs[(xx,yy)]
        rgb, depth = key
        struts.append(box('FrameSourceMark', (width,.18,height), (x+width/2-82,depth,42-y-height/2),
                          source_material('Frame_Source', rgb, .7264150977134705), parent, 0))
    detail = merge(struts, 'FrameSourceDetails')
    detail['source_profile'] = 'sharedassets2_2519.png opaque nonblack RGB, merged rectangular solids'
    detail['source_modulation'] = .7264150977134705
    return detail


def merge(objects, name):
    """Group same-material hardware in one mesh; every component remains a solid."""
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + '_Mesh'
    return obj


def make_backplate():
    root = new_scene('Backplate')
    root['dimensions_xyz_godot'] = [164, 84, 33]
    traced_backplate(root)
    box('RecessedBacking', (119.7, .9, 58.7), (0, 25.15, -1.5), 'Frame_DeepShadow', root, .15)
    source_frame_details(root)
    for side, s in [('L', -1), ('R', 1)]:
        box('BearingHousing_' + side, (13.8, 15.2, 21), (s*68.4, 2, -.5), 'Frame_DeepShadow', root, 1)
        cylinder('FixedBearing_' + side, 7.9, 7, (s*65.3, 0, 0), 'Frame_DeepShadow', root, bevel=.35)
        cylinder('FixedBearingInset_' + side, 5.25, 7.3, (s*65.3, 0, 0), 'Frame_Charcoal', root, bevel=.2)
    ribs = []
    for s in [-1, 1]:
        for z in [-14, -4, 18]:
            ribs.append(box('SideReinforcement', (14.7, 5, 2.7), (s*73, 1.3, z), 'Frame_Charcoal', root, .25))
    merge(ribs, 'SideReinforcementRibs')
    bolts = []
    for x, z in [(-45, 34), (48, 34), (-38, -33), (38, -33), (-68, 19), (68, 19)]:
        bolts.append(cylinder('MountingBolt', 1.25, 1.2, (x, 7.7 if z < -30 else 2.4, z), 'Frame_Charcoal', root, axis='Y', vertices=6, bevel=.15))
    merge(bolts, 'MountingBolts')
    # Keep the source's dim olive idle indicator visible ahead of the bezel.
    box('AlarmBezel', (9, 4, 8), (60, 6.1, 36), 'Frame_DeepShadow', root, .7)
    lamp = box('AlarmLamp', (5.2, 1.4, 4.8), (60, -.65, 36), 'Alarm_Red', root, .7)
    lamp['runtime_control'] = 'Duplicate material before changing alpha/emission; source warning keyframes drive this mesh only.'
    return save_asset(root, 'Backplate')


def make_tread():
    root = new_scene('Tread')
    root['pivot'] = 'X-axis at (0,0,0); +90 degrees lowers the tread toward Blender -Z / Godot -Y.'
    root['standing_surface'] = 'X[-48,48], Blender Y[-59,-2], Z=4. Godot Z[2,59], Y=4, relative to the source hinge at PNG(61,23).'
    root['source_pose_count_replaced'] = 13
    root['tread_width'] = 96.0
    root['tread_depth'] = 59.0
    recessed_tread(root)
    box('TreadInset', (86, 48.6, .7), (0, -30.3, 3.57), 'Tread_InsetTeal', root, .25)
    edges = [
        source_front_lip(root),
        box('RearEdge', (88, 1.6, 1), (0, -3.2, 3.4), 'Edges_BrushedSteel', root, .2),
        box('SideEdgeL', (1.5, 53, .8), (-46.5, -30.4, 3.5), 'Edges_BrushedSteel', root, .15),
        box('SideEdgeR', (1.5, 53, .8), (46.5, -30.4, 3.5), 'Edges_BrushedSteel', root, .15),
    ]
    merge(edges, 'TreadEdgeRails')
    strips = []
    for x in [-28, -14, 0, 14, 28]:
        strips.append(box('GripRib', (.8, 43, .24), (x, -30.5, 3.98-.12), 'Tread_DeepTeal', root, .09))
    merge(strips, 'TreadGripRibs')
    box('TreadUndersidePanel', (85, 46, .6), (0, -30.5, -3.7), 'Hardware_Charcoal', root, .25)
    braces = []
    for x in [-38, 38]:
        braces.append(box('UndersideRib', (3.5, 52, 1.6), (x, -28.5, -4), 'Frame_DeepShadow', root, .4))
    merge(braces, 'TreadUndersideRibs')
    cylinder('HingeShaft', 3.25, 118, (0, 0, 0), 'Hardware_Charcoal', root, vertices=32, bevel=.25)
    links = []
    for x in [-42, 42]:
        links.append(box('HingeLeaf', (7.2, 9, 3.4), (x, -3, -2), 'Gears_Gunmetal', root, .45))
    merge(links, 'TreadHingeLeaves')
    for side, s in [('L', -1), ('R', 1)]:
        annular_gear('GearLeft' if side == 'L' else 'GearRight', s*55, root)
        cylinder('GearHub_' + side, 6.5, 7.2, (s*55, 0, 0), 'Hardware_Charcoal', root, vertices=32, bevel=.25)
        cylinder('GearHubCap_' + side, 3.6, 7.8, (s*55, 0, 0), 'Bolts_PaleSteel', root, vertices=8, bevel=.22)
    screws = []
    for x in [-43.5, 43.5]:
        for y in [-6.3, -54.7]:
            screws.append(cylinder('TreadBolt', .95, .28, (x, y, 3.86), 'Bolts_PaleSteel', root, axis='Z', vertices=6, bevel=.06))
    merge(screws, 'TreadFasteners')
    root.rotation_mode = 'XYZ'
    for frame in range(13):
        root.rotation_euler.x = frame * math.pi / 24
        root.keyframe_insert(data_path='rotation_euler', index=0, frame=frame, group='X hinge fold')
    root.animation_data.action.name = 'Fold'
    root.animation_data.action['description'] = '13 authored keys; 0 to 90 degrees around +X, 0..12 at 60 fps (0.2 s).'
    for curve in root.animation_data.action.fcurves:
        for key in curve.keyframe_points:
            key.interpolation = 'LINEAR'
    bpy.context.scene.frame_set(0)
    return save_asset(root, 'Tread')


def inspect_asset(name):
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == 'MESH']
    report = {'file': name + '.blend', 'scene': scene.name, 'mesh_objects': len(meshes),
              'mesh_names': sorted(o.name for o in meshes), 'materials': sorted(m.name for m in bpy.data.materials if m.users),
              'actions': [a.name for a in bpy.data.actions], 'objects': [], 'all_base_meshes_closed': True}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bad = sum(not e.is_manifold for e in bm.edges)
        badverts = sum(not v.is_manifold for v in bm.verts)
        volume = bm.calc_volume(signed=True)
        bm.free()
        evaluated = obj.evaluated_get(depsgraph)
        evaluated_mesh = evaluated.to_mesh()
        bm = bmesh.new()
        bm.from_mesh(evaluated_mesh)
        eval_bad = sum(not e.is_manifold for e in bm.edges)
        eval_volume = bm.calc_volume(signed=True)
        bm.free()
        evaluated.to_mesh_clear()
        row = {'name': obj.name, 'parent': obj.parent.name if obj.parent else None,
               'vertices': len(obj.data.vertices), 'faces': len(obj.data.polygons),
               'nonmanifold_edges': bad, 'nonmanifold_vertices': badverts,
               'volume': round(volume, 5), 'evaluated_nonmanifold_edges': eval_bad,
               'evaluated_volume': round(eval_volume, 5)}
        if 'gear_teeth' in obj:
            row.update(teeth=obj['gear_teeth'], axial_width=obj['gear_axial_width'],
                       bore_diameter=obj['gear_bore_diameter'], outer_diameter=obj['gear_outer_diameter'])
        report['objects'].append(row)
        assert not bad and not badverts and not eval_bad and volume > 0 and eval_volume > 0, row
    return report


def save_asset(root, name):
    scene = bpy.context.scene
    for image in bpy.data.images:
        assert image.name in ('Render Result', 'Viewer Node'), 'No image textures allowed.'
    source_names = ['sharedassets2_2519.png'] if name == 'Backplate' else ['sharedassets2_1700.png', 'sharedassets2_373.png']
    scene['source_artwork_sha256'] = json.dumps({n: hashlib.sha256((SOURCE/n).read_bytes()).hexdigest() for n in source_names})
    scene['asset_contract'] = 'One static frame / one moving plank. No sprites, hidden poses, frame meshes or geometry JSON.'
    scene['native_axes'] = 'Z up; -Y front; X hinge axis. glTF/Godot: Y up; +Z front.'
    text = bpy.data.texts.new('READ ME - editable mechanical model')
    text.write('This is the authored '+name+' mechanical model.\n'
               'Every mesh is a closed, editable solid. Bevel and weighted-normal modifiers remain editable.\n'
               'Blender X-right / Z-up / -Y-front imports to Godot X-right / Y-up / +Z-front.\n'
               'Root and hinge origin are (0,0,0), source pixel (61,23). Tread top is Z=4 at rest.\n'
               'TreadHinge +X 90 degrees lowers the 96-wide, 59-deep plank.\n'
               'Fold: frames 0..12 at 60 fps, 0.2 s. Only the hinge is animated.\n'
               'AlarmLamp in Backplate has its own material for runtime warning flashes.\n'
               'Source PNGs informed palette and silhouette; no raster images are used by these models.\n'
               'To inspect both files together, use Tools/render_mechanical_preview.py.\n')
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.shading.type = 'MATERIAL'
                space.region_3d.view_distance = 205
                space.region_3d.view_location = (0, -5, -5)
                space.region_3d.view_rotation = Quaternion((1, 0, 0), math.pi/2)
                space.region_3d.view_perspective = 'ORTHO'
    report = inspect_asset(name)
    scene['mechanical_validation'] = json.dumps(report, sort_keys=True)
    path = ASSETS / (name + '.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    reloaded = inspect_asset(name)
    assert reloaded == report
    report['file_bytes'] = path.stat().st_size
    report['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    report['reload_verified'] = True
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')), export_format='GLB',
                              export_apply=True, export_animations=True, export_force_sampling=True,
                              export_frame_range=True, export_yup=True, export_extras=True)
    return report


if __name__ == '__main__':
    result = {'Backplate': make_backplate(), 'Tread': make_tread()}
    (OUT/'mechanical-model-validation.json').write_text(json.dumps(result, indent=2))
    print('MECHANICAL_BLEND_BUILD_PASS', json.dumps({k: {'meshes': v['mesh_objects'], 'bytes': v['file_bytes']} for k, v in result.items()}))
