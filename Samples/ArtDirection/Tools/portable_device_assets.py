"""Shared portable pixel/material export; runtime assets never point to a level."""

import copy
import filecmp
import hashlib
import shutil
from import_inari import Image, multiply, PPtr


def collect_visuals(scene, ids):
    """Flatten source sprite renderers and Tilemap cells, retaining source order."""
    visuals = [copy.deepcopy(v) for v in scene["sprites"] if v.get("go") in ids]
    for layer in scene["tiles"]:
        if layer.get("go") not in ids:
            continue
        for cell in layer["tiles"]:
            local = cell[4] + [
                (cell[0] + layer["anchor"][0]) * 16,
                (-cell[1] - layer["anchor"][1]) * 16,
            ]
            visuals.append(
                dict(
                    sprite=cell[2],
                    tilemap_go=layer["go"],
                    transform=multiply(layer["transform"], local),
                    sort=layer["sort"],
                    color=cell[3],
                    flip=[False, False],
                    material="",
                    visible=True,
                )
            )
    return visuals


def source_slicing(objects, gos, visuals, sprites):
    """Read native borders/trim for the selected non-simple SpriteRenderers."""
    result = {}
    for visual in visuals:
        if visual.get("mode", 0) == 0:
            continue
        renderer = next(
            objects[c["component"]["m_PathID"]]
            for c in gos[visual["go"]]["m_Component"]
            if objects[c["component"]["m_PathID"]].type.name == "SpriteRenderer"
        )
        data = renderer.read_typetree()
        assert data["m_SpriteTileMode"] == 0
        sprite = PPtr(**data["m_Sprite"], assetsfile=renderer.assets_file).read()
        info = sprites[visual["sprite"]]
        width, height = sprite.m_Rect.width, sprite.m_Rect.height
        offset = sprite.m_RD.textureRectOffset
        trim = [offset.x, height - offset.y - info["size"][1], *info["size"]]
        pivot = [sprite.m_Pivot.x, 1 - sprite.m_Pivot.y]
        expected = [trim[0] - pivot[0] * width, trim[1] - pivot[1] * height]
        assert all(abs(a - b) < 0.001 for a, b in zip(expected, info["offset"]))
        border = sprite.m_Border
        result[visual["sprite"]] = dict(
            size=[width, height],
            pivot=pivot,
            border=[border.x, border.w, border.z, border.y],
            trim=trim,
        )
    return result


def copy_if_changed(source, destination):
    # An open editor may memory-map WAV files. Do not rewrite identical assets.
    if not destination.is_file() or not filecmp.cmp(source, destination, shallow=False):
        shutil.copyfile(source, destination)


def local_material(value, original, package):
    if isinstance(value, dict):
        for k, v in value.items():
            if k == "path" and isinstance(v, str):
                src = original / v
                digest = hashlib.sha256(src.read_bytes()).hexdigest()[:16]
                dest = package / "Assets/Shared" / (digest + src.suffix)
                dest.parent.mkdir(parents=True, exist_ok=True)
                copy_if_changed(src, dest)
                value[k] = "Shared/" + dest.name
            else:
                local_material(v, original, package)
    elif isinstance(value, list):
        for child in value:
            local_material(child, original, package)


def export_artwork(
    original,
    package,
    folder,
    sprites,
    materials,
    visuals,
    sprite_keys,
    origin,
    slicing=None,
):
    sprite_info = {}
    for key in sorted(sprite_keys):
        info = copy.deepcopy(sprites[key])
        path = original / info.get("path", f"atlas_{info.get('atlas')}.png")
        with Image.open(path) as atlas:
            x, y, w, h = info["region"]
            pixels = atlas.crop((x, y, x + w, y + h)).convert("RGBA")
            pixels.save(folder / (key + ".png"))
        info.update(
            path=key + ".png",
            region=[0, 0, w, h],
            pixel_sha256=hashlib.sha256(pixels.tobytes()).hexdigest(),
        )
        sprite_info[key] = info
        if slicing is not None:
            info["slicing"] = slicing.get(key, {})

    for visual in visuals:
        pose = visual.get("spatial", {}).get("transform", visual["transform"])
        visual["transform"] = pose[:4] + [pose[4] - origin[0], pose[5] - origin[1]]
        visual.pop("spatial", None)
        mat = copy.deepcopy(materials.get(visual.get("material", ""), {}))
        local_material(mat, original, package)
        visual["material"] = mat
    return sprite_info
