#!/usr/bin/env python3
"""Author two editable mechanical assets from the original source artwork.

Run with Blender 4.3+: blender -b --python Tools/build_mechanical_models.py
Optional: append -- /absolute/inspection/output for a validation JSON and GLBs.
Add --tread-only after that path to preserve Backplate.blend byte-for-byte.
Regeneration replaces manual changes to Backplate.blend and Tread.blend.
Units match the original 2D artwork; Blender Z up / -Y forward becomes
Godot Y up / +Z forward. Native .blend files are the runtime model sources.
"""
from pathlib import Path
import bpy
import bmesh
import hashlib
import io
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
    'Alarm_Red': ('d33c34', .25, .27),
}
MATS = {}
PARTS = []
TOP_IMAGE = None
TOP_CROP = (13, 25, 109, 83)
FOLD_BOTTOMS = [5, 7, 9, 19, 34, 43, 53, 56, 59, 60]
FOLD_DEGREES = [math.degrees(math.asin(bottom / math.hypot(60, 5)) - math.atan2(5, 60))
                for bottom in FOLD_BOTTOMS] + [84.0, 88.0, 90.0]


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
    global MATS, PARTS, TOP_IMAGE
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    MATS, PARTS, TOP_IMAGE = {}, [], None
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


def fixed_hinge_cover(parent):
    """A fixed, closed annular shaft sleeve carrying the stationary teal strip.

    It surrounds the rotating 3.25-radius shaft with a 3.4-radius bore. Its
    4-radius outside is real curved geometry; no camera-facing plane is used.
    """
    steps, outer, inner, width = 96, 4.0, 3.4, 96.0
    vertices = [(x, radius*math.cos(i*2*math.pi/steps), radius*math.sin(i*2*math.pi/steps))
                for x, radius in [(-width/2, outer), (width/2, outer),
                                  (-width/2, inner), (width/2, inner)] for i in range(steps)]
    faces = []
    for i in range(steps):
        j = (i+1) % steps
        faces.extend([(i, j, steps+j, steps+i),
                      (i, 2*steps+i, 2*steps+j, j),
                      (steps+i, steps+j, 3*steps+j, 3*steps+i),
                      (2*steps+i, 3*steps+i, 3*steps+j, 2*steps+j)])
    obj = mesh('HingeCover', vertices, faces, 'Hardware_Charcoal', parent, 0)
    source = Image.open(SOURCE/'sharedassets2_373.png').convert('RGBA').crop((13, 19, 109, 27))
    for y in range(source.height):
        for x in range(source.width):
            pixel = source.getpixel((x, y))
            source.putpixel((x, y), (*pixel[:3], 255) if y < 6 and pixel[3] > 128 else (0, 0, 0, 255))
    encoded = io.BytesIO()
    source.save(encoded, format='PNG')
    png = encoded.getvalue()
    image = bpy.data.images.new('HingeCover_Source373_Packed', 96, 8, alpha=True)
    image.source = 'FILE'
    image.filepath = '//HingeCover_Source373_Packed.png'
    image.colorspace_settings.name = 'sRGB'
    image.pack(data=png, data_len=len(png))
    image['source_file'] = 'sharedassets2_373.png'
    image['source_crop_xyxy_exclusive'] = [13, 19, 109, 27]
    image['authoring'] = 'Opaque source RGB rows19..24; lower rows25..26 black to avoid painting moving panel on fixed cover; alpha-hidden RGB discarded.'
    mat = bpy.data.materials.new('HingeCover_SourceAlbedo')
    mat.use_nodes = True
    mat.diffuse_color = (1, 1, 1, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (1, 1, 1, 1)
    shader.inputs['Metallic'].default_value = .25
    shader.inputs['Roughness'].default_value = .45
    node = mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.name = 'Original stationary hinge strip, nearest pixels'
    node.image, node.interpolation, node.extension = image, 'Closest', 'EXTEND'
    mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
    mat['source_profile'] = 'Stationary original green header x13..108 y19..24 on fixed curved sleeve; bottom2rows black, no texture alpha.'
    obj.data.materials.append(mat)
    uv = obj.data.uv_layers.new(name='SourceHingeCoverUV')
    for face in obj.data.polygons:
        for loop in face.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv.data[loop].uv = ((point.x+48)/96, (point.z+4)/8)
        # The outside uses source colors. Bore and end faces remain gunmetal.
        if face.index % 4 == 0:
            face.material_index = 1
    obj['shaft_bore_radius'] = inner
    obj['outer_radius'] = outer
    obj['shaft_width'] = width
    obj['mechanical_role'] = 'Fixed coaxial hinge cover. Moving body/leaves have a4.15-radius clearance notch; rotating shaft radius3.25 fits inside bore3.4.'
    return obj


def cut_fixed_hinge_clearance(objects):
    """Remove the sleeve's swept volume from moving deck and attachment leaves."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=4.15, depth=98, rotation=(0, math.pi/2, 0))
    cutter = bpy.context.object
    cutter.name = 'Authoring fixed sleeve clearance cutter'
    cutter.data.materials.append(material('Hardware_Charcoal'))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        # Preserve the existing leaf bevel before making the structural notch.
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        modifier = obj.modifiers.new('Fixed hinge sleeve radial clearance', 'BOOLEAN')
        modifier.operation, modifier.solver, modifier.object = 'DIFFERENCE', 'EXACT', cutter
        modifier.material_mode = 'TRANSFER'
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj['hinge_sleeve_clearance_radius'] = 4.15
        obj['hinge_sleeve_clearance'] = 'Coaxial through-notch, invariant under X-axis rotation; shaft itself is unchanged.'
    bpy.data.objects.remove(cutter, do_unlink=True)


def source_top_material():
    """One packed nearest-filter albedo, on the actual closed plank's top faces.

    RGB is taken only from opaque pixels in the fully folded original frame.
    Transparent pixels are cleared, never sampled for their hidden RGB. The
    native geometry supplies silhouette and depth; texture alpha is not used.
    """
    global TOP_IMAGE
    name = 'Panel_SourceAlbedo'
    if name in MATS:
        return MATS[name]
    source = Image.open(SOURCE / 'sharedassets2_373.png').convert('RGBA').crop(TOP_CROP)
    source.putdata([(*rgb[:3], 255) if rgb[3] > 128 else (0, 0, 0, 255)
                    for rgb in source.getdata()])
    encoded = io.BytesIO()
    source.save(encoded, format='PNG')
    png = encoded.getvalue()
    TOP_IMAGE = bpy.data.images.new('TreadPanel_Source373_Packed', source.width, source.height, alpha=True)
    TOP_IMAGE.source = 'FILE'
    TOP_IMAGE.filepath = '//TreadPanel_Source373_Packed.png'
    TOP_IMAGE.colorspace_settings.name = 'sRGB'
    TOP_IMAGE.pack(data=png, data_len=len(png))
    TOP_IMAGE['source_file'] = 'sharedassets2_373.png'
    TOP_IMAGE['source_crop_xyxy_exclusive'] = list(TOP_CROP)
    TOP_IMAGE['authoring'] = 'Opaque source RGB only; alpha-hidden RGB discarded. Packed albedo, not a sprite plane.'
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (1, 1, 1, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (1, 1, 1, 1)
    shader.inputs['Metallic'].default_value = .2
    shader.inputs['Roughness'].default_value = .5
    image = mat.node_tree.nodes.new('ShaderNodeTexImage')
    image.name = 'Original folded panel, nearest pixels'
    image.image = TOP_IMAGE
    image.interpolation = 'Closest'
    image.extension = 'EXTEND'
    mat.node_tree.links.new(image.outputs['Color'], shader.inputs['Base Color'])
    mat['source_profile'] = 'sharedassets2_373.png crop x13..108 y25..82; UV locked to native X/Y surface, no alpha cutout'
    MATS[name] = mat
    return mat


def paint_source_top(obj):
    """Continuous source-pixel UVs across the real rim, recess and front lip."""
    index = len(obj.data.materials)
    obj.data.materials.append(source_top_material())
    uv = obj.data.uv_layers.new(name='SourcePanelUV')
    painted = 0
    for face in obj.data.polygons:
        for loop in face.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv.data[loop].uv = ((point.x + 48) / 96, (point.y + 60) / 58)
        if face.normal.z > .5:
            face.material_index = index
            painted += 1
    obj['source_top_faces'] = painted
    obj['source_uv_mapping'] = 'PNG(x,y)=(X+61,23-Y); packed crop (13,25)-(109,83), nearest'
    return obj


def recessed_tread(parent):
    """One closed plank with two actual one-pixel-wide recessed border steps."""
    def rectangle(x0, x1, y0, y1, z):
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    # A 0.001-unit closure land avoids a zero-area edge where the source inset's
    # bottom border meets the structural front lip. It is far below one pixel.
    vertices = (rectangle(-48, 48, -56, -2, -3.6) + rectangle(-48, 48, -56, -2, 4)
                + rectangle(-44, 44, -55.999, -3, 4)
                + rectangle(-43, 43, -55, -4, 3.76)
                + rectangle(-42, 42, -54, -5, 3.6))
    faces = [(3, 2, 1, 0), (16, 17, 18, 19)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, j+4, i+4))
        for start in (4, 8, 12):
            faces.append((i+start, j+start, j+start+4, i+start+4))
    obj = mesh('TreadBody', vertices, faces, 'Tread_DeepTeal', parent, 0)
    obj['source_panel_bounds'] = 'outer pocket PNG x17..104 y26..78; inner border x18..103 y27..77; field x19..102 y28..76'
    obj['recess_depth'] = .4
    return paint_source_top(obj)


def source_front_lip(parent):
    """One closed rail with the exact nine READY rows and folded corner profile.

    A shared-vertex surface grid keeps each groove/highlight editable and manifold.
    Only READY pixels x13..108/y19..27 are used. Transparent pixels at the two
    bottom corners are omitted; transparent grey/teal shapes are never modeled.
    Its stepped 1..4-unit depth matches the folded panel's bottom corner cuts,
    without changing any front-projected X/Z pixel or source RGB at READY.
    """
    image = Image.open(SOURCE / 'sharedassets2_1700.png').convert('RGBA')
    pixels = {(x, y): image.getpixel((x, y))[:3] for y in range(19, 28) for x in range(13, 109)
              if image.getpixel((x, y))[3] > 128}
    front_depth = lambda x: -min(60, 57 + min(x-13, 108-x))
    cells = {(x, depth, y): rgb for (x, y), rgb in pixels.items()
             for depth in range(front_depth(x), -56)}
    vertices, indices, faces, palettes = [], {}, [], []
    def vertex(x, depth, y):
        key = (x, depth, y)
        if key not in indices:
            indices[key] = len(vertices)
            vertices.append((x-61, depth, 23-y))
        return indices[key]
    sides = [((-1,0,0), [(0,0,0),(0,1,0),(0,1,1),(0,0,1)]),
             ((1,0,0), [(1,0,0),(1,0,1),(1,1,1),(1,1,0)]),
             ((0,-1,0),[(0,0,0),(0,0,1),(1,0,1),(1,0,0)]),
             ((0,1,0), [(0,1,0),(1,1,0),(1,1,1),(0,1,1)]),
             ((0,0,-1),[(0,0,0),(1,0,0),(1,1,0),(0,1,0)]),
             ((0,0,1), [(0,0,1),(0,1,1),(1,1,1),(1,0,1)])]
    for (x, depth, y), rgb in cells.items():
        for (dx, dd, dy), corners in sides:
            if (x+dx, depth+dd, y+dy) not in cells:
                faces.append(tuple(vertex(x+xx, depth+dd, y+yy) for xx, dd, yy in corners))
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
    obj['folded_corner_profile'] = 'PNG rows79/80/81/82 widths96/94/92/90; native Y[-60,-56]'
    return paint_source_top(obj)


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
    fixed_hinge_cover(root)
    return save_asset(root, 'Backplate')


def make_tread():
    root = new_scene('Tread')
    root['pivot'] = 'X-axis at (0,0,0); +90 degrees lowers the tread toward Blender -Z / Godot -Y.'
    root['standing_surface'] = 'X[-48,48], Blender Y[-60,-2], rim Z=4, recessed field Z=3.6. Godot Z[2,60], rim Y=4, source hinge PNG(61,23).'
    root['source_pose_count_replaced'] = 13
    root['tread_width'] = 96.0
    root['tread_depth'] = 60.0
    root['source_panel_material'] = 'One packed nearest-filter source-derived albedo on actual closed top faces; no image planes or texture alpha cutout.'
    root['source_fold_bottoms'] = FOLD_BOTTOMS + [60, 60, 60]
    root['fold_angle_degrees'] = FOLD_DEGREES
    recessed_tread(root)
    source_front_lip(root)
    box('TreadUndersidePanel', (85, 46, .6), (0, -30.5, -3.7), 'Hardware_Charcoal', root, .25)
    braces = []
    for x in [-38, 38]:
        braces.append(box('UndersideRib', (3.5, 52, 1.6), (x, -28.5, -4), 'Frame_DeepShadow', root, .4))
    merge(braces, 'TreadUndersideRibs')
    cylinder('HingeShaft', 3.25, 118, (0, 0, 0), 'Hardware_Charcoal', root, vertices=32, bevel=.25)
    links = []
    for x in [-42, 42]:
        links.append(box('HingeLeaf', (7.2, 9, 3.4), (x, -3, -2), 'Gears_Gunmetal', root, .45))
    leaves = merge(links, 'TreadHingeLeaves')
    cut_fixed_hinge_clearance([bpy.data.objects['TreadBody'], leaves])
    for side, s in [('L', -1), ('R', 1)]:
        annular_gear('GearLeft' if side == 'L' else 'GearRight', s*55, root)
        cylinder('GearHub_' + side, 6.5, 7.2, (s*55, 0, 0), 'Hardware_Charcoal', root, vertices=32, bevel=.25)
        cylinder('GearHubCap_' + side, 3.6, 7.8, (s*55, 0, 0), 'Bolts_PaleSteel', root, vertices=8, bevel=.22)
    root.rotation_mode = 'XYZ'
    for frame, degrees in enumerate(FOLD_DEGREES):
        root.rotation_euler.x = math.radians(degrees)
        root.keyframe_insert(data_path='rotation_euler', index=0, frame=frame, group='X hinge fold')
    root.animation_data.action.name = 'Fold'
    root.animation_data.action['description'] = '13 source-silhouette-fitted +X hinge keys, 0..90 degrees over 0..12 at 60 fps (0.2 s), continuous linear interpolation between keys.'
    root.animation_data.action['source_fold_fit'] = 'Frames0..9 invert bottom=60*sin(angle)+5*cos(angle); frames10..12 continue monotonically84,88,90 degrees.'
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
              'actions': [a.name for a in bpy.data.actions], 'objects': [], 'all_base_meshes_closed': True,
              'packed_images': [{'name': i.name, 'size': list(i.size), 'packed': bool(i.packed_file),
                                 'colorspace': i.colorspace_settings.name}
                                for i in bpy.data.images if i.name not in ('Render Result', 'Viewer Node')],
              'image_materials': []}
    for mat in bpy.data.materials:
        if not mat.users or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                report['image_materials'].append({'material': mat.name, 'image': node.image.name,
                                                'filter': node.interpolation, 'alpha_linked': bool(node.outputs['Alpha'].links)})
                assert node.image.packed_file and node.interpolation == 'Closest'
                assert not node.outputs['Alpha'].links, 'Native mesh opacity must not come from sprite alpha.'
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
               'evaluated_volume': round(eval_volume, 5),
               'uv_layers': list(obj.data.uv_layers.keys())}
        if 'gear_teeth' in obj:
            row.update(teeth=obj['gear_teeth'], axial_width=obj['gear_axial_width'],
                       bore_diameter=obj['gear_bore_diameter'], outer_diameter=obj['gear_outer_diameter'])
        report['objects'].append(row)
        assert not bad and not badverts and not eval_bad and volume > 0 and eval_volume > 0, row
    return report


def save_asset(root, name):
    scene = bpy.context.scene
    for image in bpy.data.images:
        assert image.name in ('Render Result', 'Viewer Node', 'TreadPanel_Source373_Packed', 'HingeCover_Source373_Packed')
        if image.name == 'TreadPanel_Source373_Packed':
            assert name == 'Tread' and image.packed_file
        if image.name == 'HingeCover_Source373_Packed':
            assert name == 'Backplate' and image.packed_file
    source_names = ['sharedassets2_2519.png', 'sharedassets2_373.png'] if name == 'Backplate' else ['sharedassets2_1700.png', 'sharedassets2_373.png']
    scene['source_artwork_sha256'] = json.dumps({n: hashlib.sha256((SOURCE/n).read_bytes()).hexdigest() for n in source_names})
    scene['asset_contract'] = 'One static frame / one moving plank. No sprites, hidden poses, frame meshes or geometry JSON.'
    scene['native_axes'] = 'Z up; -Y front; X hinge axis. glTF/Godot: Y up; +Z front.'
    text = bpy.data.texts.new('READ ME - editable mechanical model')
    text.write('This is the authored '+name+' mechanical model.\n'
               'Every mesh is a closed, editable solid. Bevel and weighted-normal modifiers remain editable.\n'
               'Blender X-right / Z-up / -Y-front imports to Godot X-right / Y-up / +Z-front.\n'
               'Root and hinge origin are (0,0,0), source pixel (61,23). Tread top is Z=4 at rest.\n'
               'TreadHinge +X 90 degrees lowers the 96-wide, 60-deep plank.\n'
               'Fold: 13 silhouette-fitted keys over frames 0..12 at 60 fps, 0.2 s. Only the hinge is animated.\n'
               'AlarmLamp in Backplate has its own material for runtime warning flashes.\n'
               'Backplate and READY front rail use source-colored native solids.\n'
               'The stationary teal hinge strip is painted onto a real closed shaft sleeve in Backplate.blend.\n'
               'Its packed nearest albedo uses original source RGB; the moving deck/leaves have radial clearance.\n'
               'Tread top uses one packed nearest-filter albedo authored from opaque original folded-frame pixels.\n'
               'Its frame, double recessed border, thickness and clipped corners are real closed geometry.\n'
               'There are no sprite planes, alpha-cutout silhouettes, per-pose meshes or runtime geometry JSON.\n'
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
    result = {} if '--tread-only' in sys.argv else {'Backplate': make_backplate()}
    result['Tread'] = make_tread()
    (OUT/'mechanical-model-validation.json').write_text(json.dumps(result, indent=2))
    print('MECHANICAL_BLEND_BUILD_PASS', json.dumps({k: {'meshes': v['mesh_objects'], 'bytes': v['file_bytes']} for k, v in result.items()}))
