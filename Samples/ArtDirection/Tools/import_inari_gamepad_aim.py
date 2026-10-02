"""Extract native gamepad aim renderers through PlayerStateMachine references."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump, rgba
from unity_scene_spatial import WorldTransforms
from unity_sprite_effects import sprite_effect_mesh
from extract_inari_uv_programs import extract


def export(source, decompiled, output):
    env = UnityPy.load(str(source / "level1"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    transforms = {o.path_id: o.read_typetree() for o in env.objects if o.type.name == "Transform"}
    by_go = {v["m_GameObject"]["m_PathID"]: k for k, v in transforms.items()}
    world = WorldTransforms(transforms)
    player = next(
        o
        for o in env.objects
        if o.type.name == "MonoBehaviour"
        and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "PlayerStateMachine"
    )
    state = player.read_typetree()

    def reference(key):
        return PPtr(**state[key], assetsfile=player.assets_file).deref()

    def pose(go):
        return world.sprite_plane(by_go[go], 16)["transform"]

    origin = pose(state["m_GameObject"]["m_PathID"])[4:]
    holder = reference("ShurikenAimHolder")
    holder_pose = pose(holder.path_id)
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.texture_assets, importer.sprites, importer.images = {}, {}, {}
    importer.materials, importer.material_details = {}, {}
    result = {"holder_offset": [a - b for a, b in zip(holder_pose[4:], origin)], "programs": {}}
    audit = Path("tmp/art-direction/gamepad-aim")
    audit.mkdir(parents=True, exist_ok=True)

    def program(material):
        data = material.read_typetree()
        code, params, proof = extract(material.read().m_Shader.read(), set(data["m_ValidKeywords"]))
        name = data["m_Name"]
        (audit / (name + ".dxbc")).write_bytes(code)
        (audit / (name + ".params")).write_bytes(params)
        result["programs"][name] = proof

    line = reference("gamdPadAimLineRenderer")
    data = line.read_typetree()
    mat = PPtr(**data["m_Materials"][0], assetsfile=line.assets_file).deref()
    saved = mat.read_typetree()["m_SavedProperties"]
    floats, colors, textures = (dict(saved[n]) for n in ["m_Floats", "m_Colors", "m_TexEnvs"])
    tex = textures["_MainTex"]
    line_pose = pose(data["m_GameObject"]["m_PathID"])
    assert data["m_UseWorldSpace"] and not data["m_Loop"]
    result["line"] = {
        "source_id": line.path_id,
        "parameters": data["m_Parameters"],
        "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
        "color": rgba(colors["_Color"]),
        "dash_length": floats["_DashLength"],
        "gap_length": floats["_GapLength"],
        "texture": importer.texture_asset(PPtr(**tex["m_Texture"], assetsfile=mat.assets_file)),
        "texture_st": [tex["m_Scale"][a] for a in "xy"] + [tex["m_Offset"][a] for a in "xy"],
        "offset": [a - b for a, b in zip(line_pose[4:], holder_pose[4:])],
        "world_space": True,
    }
    program(mat)
    renderer = reference("gamePadAimPointer")
    data = renderer.read_typetree()
    key = importer.sprite(PPtr(**data["m_Sprite"], assetsfile=renderer.assets_file))
    info = importer.sprites[key]
    info["effect_mesh"] = sprite_effect_mesh(
        importer, PPtr(**data["m_Sprite"], assetsfile=renderer.assets_file).read(), 16
    )
    info["path"] = "Sprites/" + key + ".png"
    info["region"] = [0, 0, *info["size"]]
    (output / "Sprites").mkdir(exist_ok=True)
    importer.images[key].save(output / info["path"])
    mat_pointer = PPtr(**data["m_Materials"][0], assetsfile=renderer.assets_file)
    blend = importer.material(mat_pointer)
    mat = mat_pointer.deref()
    # Scope this native material to its renderer; another asset can share its name.
    name = "GamepadAim/" + mat.read_typetree()["m_Name"]
    importer.material_details[name] = importer.material_details.pop(mat.read_typetree()["m_Name"])
    pointer_pose = pose(data["m_GameObject"]["m_PathID"])
    pointer_pose[4:] = [0, 0]
    result["pointer"] = {
        "source_id": renderer.path_id,
        "sprite": key,
        "transform": pointer_pose,
        "visible": True,
        "color": rgba(data["m_Color"]),
        "material": name,
        "blend": blend,
        "mode": data["m_DrawMode"],
        "size": [data["m_Size"][a] * 16 for a in "xy"],
        "flip": [data["m_FlipX"], data["m_FlipY"]],
        "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
        "layer_id": data["m_SortingLayerID"],
    }
    program(mat)
    code_path = decompiled / "PlayerStateMachine.cs"
    code = code_path.read_text(encoding="utf8")
    draw = code.split("public void DrawAimLineForGamepad()")[1].split("private void")[0]
    result["minimum_hit_distance"] = float(
        re.search(r"_raycastBuffer\[0\].distance > ([0-9.]+)f", draw).group(1)
    )
    assert "gamePadAimPointer.color = Color.yellow;" in draw
    assert "gamePadAimPointer.color = Color.cyan;" in draw
    assert "gamePadAimPointer.color = Color.white;" in draw
    result["pointer_colors"] = {
        "enemy": [1, 1, 0, 1],
        "platform": [0, 1, 1, 1],
        "free": [1, 1, 1, 1],
    }
    result["source_sha256"] = {
        n: hashlib.sha256((source / n).read_bytes()).hexdigest()
        for n in ["level1", "sharedassets1.assets", "Managed/Assembly-CSharp.dll"]
    }
    result["source_sha256"]["PlayerStateMachine.cs"] = hashlib.sha256(
        code_path.read_bytes()
    ).hexdigest()
    for filename, additions in [
        ("sprites.json", importer.sprites),
        ("materials.json", importer.material_details),
    ]:
        target = output / filename
        merged = json.loads(target.read_text(encoding="utf8"))
        merged.update(additions)
        dump(target, merged)
    dump(output / "gamepad_aim.json", result)
    print("Extracted gamepad aim line and pointer", key)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
