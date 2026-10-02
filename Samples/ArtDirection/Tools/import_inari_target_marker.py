"""Extract the persistent player's WeakMark hierarchy and dotted aiming line.

Only source pixels are exported. The native fragment programs are retained as
hash evidence; disassembly remains in the ignored audit directory.
"""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump, rgba
from unity_scene_spatial import WorldTransforms
from unity_scene_lighting import light_settings
from unity_sprite_effects import sprite_effect_mesh
from extract_inari_uv_programs import extract


def export(source, output, audit):
    env = UnityPy.load(str(source / "level1"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    objects = {obj.path_id: obj for obj in env.objects}
    transforms = {
        obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"
    }
    by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}
    world = WorldTransforms(transforms)
    player = next(
        obj
        for obj in env.objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "PlayerStateMachine"
    )
    state = player.read_typetree()
    marker = PPtr(**state["WeakMarkObject"], assetsfile=player.assets_file).deref()
    controller = marker.read_typetree()
    root_go = controller["m_GameObject"]["m_PathID"]
    origin = world.sprite_plane(by_go[root_go], 16)["transform"][4:]
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.texture_assets, importer.sprites, importer.images = {}, {}, {}
    importer.materials, importer.material_details = {}, {}
    result = {
        "source_id": marker.path_id,
        "fade_in": controller["fadeInTime"],
        "fade_out_unused": controller["fadeOutTime"],
        "disappear_time": controller["disappearFadeTime"],
        "sprites": [],
        "programs": {},
    }
    audit.mkdir(parents=True, exist_ok=True)

    def program(material):
        data = material.read_typetree()
        bytecode, parameters, proof = extract(
            material.read().m_Shader.read(), set(data["m_ValidKeywords"])
        )
        name = data["m_Name"]
        (audit / (name + ".dxbc")).write_bytes(bytecode)
        (audit / (name + ".params")).write_bytes(parameters)
        result["programs"][name] = proof

    for reference in controller["spriteRenderers"]:
        renderer = PPtr(**reference, assetsfile=marker.assets_file).deref()
        data = renderer.read_typetree()
        go = data["m_GameObject"]["m_PathID"]
        spatial = world.sprite_plane(by_go[go], 16)
        spatial["transform"][4:] = [a - b for a, b in zip(spatial["transform"][4:], origin)]
        pointer = PPtr(**data["m_Sprite"], assetsfile=renderer.assets_file)
        key = importer.sprite(pointer)
        info = importer.sprites[key]
        info["effect_mesh"] = sprite_effect_mesh(importer, pointer.read(), 16)
        # Keep the cropped sprite for the shared SpriteRenderer interface, while
        # drawing the original tight mesh against its unmodified source texture.
        info["path"] = "Sprites/" + key + ".png"
        info["region"] = [0, 0, *info["size"]]
        destination = output / info["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        importer.images[key].save(destination)
        material_pointer = PPtr(**data["m_Materials"][0], assetsfile=renderer.assets_file)
        blend = importer.material(material_pointer)
        material = material_pointer.deref()
        material_data = material.read_typetree()
        name = material_data["m_Name"]
        floats = dict(material_data["m_SavedProperties"]["m_Floats"])
        colors = dict(material_data["m_SavedProperties"]["m_Colors"])
        importer.material_details[name]["base_outline"] = {
            "color": rgba(colors["_OutlineColor"]),
            "alpha": floats["_OutlineAlpha"],
            "glow": floats["_OutlineGlow"],
            "pixel_width": floats["_OutlinePixelWidth"],
            "pixel_perfect": "OUTBASEPIXELPERF_ON" in material_data["m_ValidKeywords"],
            "width": floats["_OutlineWidth"],
        }
        program(material)
        result["sprites"].append(
            {
                "go": go,
                "sprite": key,
                "transform": spatial["transform"],
                "visible": bool(objects[go].read_typetree()["m_IsActive"]),
                "color": rgba(data["m_Color"]),
                "material": name,
                "blend": blend,
                "mode": data["m_DrawMode"],
                "size": [data["m_Size"][axis] * 16 for axis in "xy"],
                "flip": [data["m_FlipX"], data["m_FlipY"]],
                "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
                "layer_id": data["m_SortingLayerID"],
            }
        )

    # Find the actual child Light2D, rather than importing unrelated player lights.
    descendants = {by_go[root_go]}
    pending = list(descendants)
    while pending:
        tid = pending.pop()
        for child in transforms[tid]["m_Children"]:
            descendants.add(child["m_PathID"])
            pending.append(child["m_PathID"])
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "Light2D":
            continue
        data = obj.read_typetree()
        tid = by_go[data["m_GameObject"]["m_PathID"]]
        if tid not in descendants:
            continue
        spatial = world.sprite_plane(tid, 16)
        spatial["transform"][4:] = [a - b for a, b in zip(spatial["transform"][4:], origin)]
        result["light"] = {
            "source_id": obj.path_id,
            "spatial": spatial,
            "type": data["m_LightType"],
            "color": rgba(data["m_Color"]),
            "energy": data["m_Intensity"],
            "radius": data["m_PointLightOuterRadius"] * 16,
            "layers": data["m_ApplyToSortingLayers"],
            "settings": light_settings(data),
        }
    line = PPtr(**state["shurikenAimPointer"], assetsfile=player.assets_file).deref()
    data = line.read_typetree()
    parameters = data["m_Parameters"]
    player_origin = world.sprite_plane(by_go[state["m_GameObject"]["m_PathID"]], 16)["transform"][
        4:
    ]
    line_transform = world.sprite_plane(by_go[data["m_GameObject"]["m_PathID"]], 16)["transform"]
    material = PPtr(**data["m_Materials"][0], assetsfile=line.assets_file).deref()
    saved = material.read_typetree()["m_SavedProperties"]
    floats, colors, textures = (dict(saved[name]) for name in ["m_Floats", "m_Colors", "m_TexEnvs"])
    main_texture = textures["_MainTex"]
    result["line"] = {
        "source_id": line.path_id,
        "parameters": parameters,
        "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
        "color": rgba(colors["_Color"]),
        "dash_length": floats["_DashLength"],
        "gap_length": floats["_GapLength"],
        "texture": importer.texture_asset(
            PPtr(**main_texture["m_Texture"], assetsfile=material.assets_file)
        ),
        "texture_st": [main_texture["m_Scale"][axis] for axis in "xy"]
        + [main_texture["m_Offset"][axis] for axis in "xy"],
        "world_space": data["m_UseWorldSpace"],
        "loop": data["m_Loop"],
        "initial_offset": [a - b for a, b in zip(line_transform[4:], player_origin)],
        "initial_points": [
            [point["x"] * 16, -point["y"] * 16, point["z"] * 16] for point in data["m_Positions"]
        ],
    }
    program(material)
    result["source_sha256"] = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest()
        for name in ["level1", "sharedassets1.assets", "Managed/Assembly-CSharp.dll"]
    }
    for filename, additions in [
        ("sprites.json", importer.sprites),
        ("materials.json", importer.material_details),
    ]:
        path = output / filename
        merged = json.loads(path.read_text(encoding="utf8"))
        merged.update(additions)
        dump(path, merged)
    dump(output / "target_marker.json", result)
    for info in importer.texture_assets.values():
        options = (output / info["path"]).with_suffix(".png.import")
        if options.exists():
            options.write_text(
                options.read_text(encoding="utf8").replace(
                    "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                ),
                encoding="utf8",
            )
    print(
        "Native target marker:",
        len(result["sprites"]),
        "sprites, light",
        result["light"]["source_id"],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
        Path("tmp/art-direction/target-marker"),
    )
