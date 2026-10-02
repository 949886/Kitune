"""Export the actual Arrow prefab, collision matrix, sprite and TrailRenderer."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, rgba
from import_inari_damage import number
from import_inari_particles import portable
from unity_scene_spatial import WorldTransforms


def save_pixels(image, output, name):
    pixels = image.convert("RGBA")
    pixels.save(output / name)
    settings = (output / name).with_suffix(".png.import")
    if settings.exists():
        text = settings.read_text(encoding="utf8")
        settings.write_text(
            text.replace("process/fix_alpha_border=true", "process/fix_alpha_border=false"),
            encoding="utf8",
        )
    return {
        "path": name,
        "size": list(pixels.size),
        "pixel_sha256": hashlib.sha256(pixels.tobytes()).hexdigest(),
    }


def material(pointer):
    value = pointer.read_typetree()
    props = value["m_SavedProperties"]
    floats, colors = dict(props["m_Floats"]), dict(props["m_Colors"])
    return {
        "name": value["m_Name"],
        "shader": pointer.read().m_Shader.read().m_ParsedForm.m_Name,
        "keywords": value["m_ValidKeywords"],
        "color": rgba(colors.get("_Color", {})),
        "alpha": floats.get("_Alpha", 1),
        "glow_color": rgba(colors.get("_GlowColor", {})),
        "glow": floats.get("_Glow", 0),
        "glow_global": floats.get("_GlowGlobal", 1),
        "floats": floats,
    }


def export(source, code, output):
    output.mkdir(parents=True, exist_ok=True)
    bundle = next(source.glob("StreamingAssets/aa/StandaloneWindows64/defaultlocalgroup*.bundle"))
    shaders = next(source.glob("StreamingAssets/aa/StandaloneWindows64/shaderassets*.bundle"))
    env = UnityPy.load(str(bundle), str(shaders))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    arrow = None
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        data = obj.read_typetree()
        if "Dic_Projecttile" in data:
            profile = dict(zip(data["Dic_Projecttile"]["keys"], data["Dic_Projecttile"]["values"]))
            arrow = PPtr(**profile["Arrow"], assetsfile=obj.assets_file)
            break
    assert arrow is not None
    projectile = arrow.read_typetree()
    root = PPtr(**projectile["m_GameObject"], assetsfile=arrow.assetsfile)
    pending, nodes, transforms = [root], [], {}
    while pending:
        pointer = pending.pop()
        go = pointer.read_typetree()
        if not go["m_IsActive"]:
            continue
        components = {}
        for reference in go["m_Component"]:
            component = PPtr(**reference["component"], assetsfile=pointer.assetsfile)
            components[component.deref().type.name] = component
        pose = components["Transform"].read_typetree()
        tid = components["Transform"].path_id
        transforms[tid] = pose
        nodes.append((go, tid, components))
        for child in pose["m_Children"]:
            transform = PPtr(**child, assetsfile=pointer.assetsfile).read_typetree()
            pending.append(PPtr(**transform["m_GameObject"], assetsfile=pointer.assetsfile))
    world = WorldTransforms(transforms)
    body = PPtr(**projectile["rigid"], assetsfile=arrow.assetsfile).read_typetree()
    collider = PPtr(**projectile["collider2D"], assetsfile=arrow.assetsfile).read_typetree()
    globals_env = UnityPy.load(str(source / "globalgamemanagers"))
    names = next(
        o.read_typetree()["layers"] for o in globals_env.objects if o.type.name == "TagManager"
    )
    physics = next(
        o.read_typetree() for o in globals_env.objects if o.type.name == "Physics2DSettings"
    )
    layer = root.read_typetree()["m_Layer"]
    mask = physics["m_LayerCollisionMatrix"][layer]
    for settings in [body, collider]:
        mask = (mask | settings["m_IncludeLayers"]["m_Bits"]) & ~settings["m_ExcludeLayers"][
            "m_Bits"
        ]
    projectile_code = (code / "Projectile.cs").read_text(encoding="utf8")
    result = {
        "prefab": root.read_typetree()["m_Name"],
        "layer": names[layer],
        "collision_layers": [name for index, name in enumerate(names) if mask & (1 << index)],
        "rigidbody": body,
        "collider": collider,
        "damage": number(projectile_code, r"Amount = ([\d.]+)f"),
        "destroy_effect": projectile["destroyEffectKey"],
        "source_sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [
                bundle,
                shaders,
                source / "globalgamemanagers",
                source / "Managed/Assembly-CSharp.dll",
                code / "Projectile.cs",
                code / "Arrow.cs",
            ]
        },
    }
    for go, tid, components in nodes:
        if "SpriteRenderer" not in components:
            continue
        renderer = components["SpriteRenderer"].read_typetree()
        assert renderer["m_Enabled"] and renderer["m_DrawMode"] == 0
        sprite = PPtr(**renderer["m_Sprite"], assetsfile=arrow.assetsfile).read()
        image = sprite.image
        offset = sprite.m_RD.textureRectOffset
        sprite_info = save_pixels(image, output, "arrow.png")
        sprite_info.update(
            {
                "name": sprite.m_Name,
                "ppu": sprite.m_PixelsToUnits,
                "offset": [
                    offset.x - sprite.m_Pivot.x * sprite.m_Rect.width,
                    sprite.m_Pivot.y * sprite.m_Rect.height - offset.y - image.height,
                ],
                "filter": sprite.m_RD.texture.read().m_TextureSettings.m_FilterMode,
            }
        )
        plane = world.sprite_plane(tid, 16.0)
        assert plane["parallel"]
        result["visual"] = {
            "sprite": sprite_info,
            "transform": plane["transform"],
            "sort": [renderer["m_SortingLayer"], renderer["m_SortingOrder"]],
            "color": rgba(renderer["m_Color"]),
            "flip": [renderer["m_FlipX"], renderer["m_FlipY"]],
            "material": material(PPtr(**renderer["m_Materials"][0], assetsfile=arrow.assetsfile)),
        }
        trail = components["TrailRenderer"].read_typetree()
        trail_material = PPtr(**trail["m_Materials"][0], assetsfile=arrow.assetsfile)
        main = dict(trail_material.read_typetree()["m_SavedProperties"]["m_TexEnvs"])["_MainTex"]
        texture = PPtr(**main["m_Texture"], assetsfile=arrow.assetsfile).read()
        result["trail"] = {
            "renderer": trail,
            "material": material(trail_material),
            "texture": {
                **save_pixels(texture.image, output, "arrow_trail.png"),
                "filter": texture.m_TextureSettings.m_FilterMode,
            },
        }
    assert "visual" in result and "trail" in result
    (output / "arrow.json").write_text(
        json.dumps(portable(result), indent=2) + "\n", encoding="utf8"
    )
    print(
        "Imported Arrow:",
        result["visual"]["sprite"]["size"],
        "collisions",
        result["collision_layers"],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/Projectiles",
    )
