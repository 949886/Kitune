"""Import native enemy outline parameters, renderer bindings and source atlas meshes."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump, rgba, PIXELS_PER_UNIT
from unity_sprite_effects import sprite_effect_mesh
from extract_inari_uv_programs import extract


def read(path):
    return json.loads(path.read_text(encoding="utf8"))


def animation_sprites(value, targets, keys):
    if isinstance(value, dict):
        if value.get("kind") == "sprite" and value.get("go") in targets:
            keys.update(frame[1] for frame in value["frames"] if frame[1])
        for child in value.values():
            animation_sprites(child, targets, keys)
    elif isinstance(value, list):
        for child in value:
            animation_sprites(child, targets, keys)


def export(source, decompiled, output, audit):
    scene = read(output / "level15.json")
    evidence = read(output / "weakpoints.json")
    materials = read(output / "materials.json")
    sprites = read(output / "sprites.json")
    manifest = read(output / "material_programs.json")
    environment = UnityPy.load(str(source / "level15"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    environment.typetree_generator = generator
    objects = {obj.path_id: obj for obj in environment.objects}
    keys, visual_ids, material_readers = set(), set(), {}
    for actor in scene["enemies"]:
        obj = objects[actor["source_id"]]
        targets = set()
        for reference in obj.read_typetree()["otherRenderers"]:
            renderer = PPtr(**reference, assetsfile=obj.assets_file).deref()
            data = renderer.read_typetree()
            targets.add(data["m_GameObject"]["m_PathID"])
            for pointer in data["m_Materials"]:
                material = PPtr(**pointer, assetsfile=renderer.assets_file).deref()
                material_readers[material.peek_name()] = material
        evidence["actors"][str(actor["go"])]["outline_visuals"] = sorted(targets)
        visual_ids.update(targets)
        animation_sprites(actor, targets, keys)
    keys.update(item["sprite"] for item in scene["sprites"] if item["go"] in visual_ids)
    importer = Importer.__new__(Importer)
    importer.output, importer.texture_assets = output, {}
    files = {}
    for key in sorted(keys):
        filename, object_id = key.rsplit("_", 1)
        if filename not in files:
            files[filename] = {
                obj.path_id: obj
                for obj in UnityPy.load(str(source / (filename + ".assets"))).objects
            }
        sprite = files[filename][int(object_id)].read()
        sprites[key]["effect_mesh"] = sprite_effect_mesh(importer, sprite, PIXELS_PER_UNIT)
    audit.mkdir(parents=True, exist_ok=True)
    for name, material in material_readers.items():
        data = material.read_typetree()
        keywords = set(data["m_ValidKeywords"])
        assert {"OUTBASE_ON", "OUTBASEPIXELPERF_ON"} <= keywords
        floats = dict(data["m_SavedProperties"]["m_Floats"])
        colors = dict(data["m_SavedProperties"]["m_Colors"])
        # The remaining compiled UV/hologram operations are neutral for this material.
        assert floats["_OffsetUvX"] == floats["_OffsetUvY"] == 0
        assert floats["_HologramMinAlpha"] == floats["_HologramMaxAlpha"] == 1
        assert all(colors["_HologramStripeColor"][channel] == 0 for channel in "rgb")
        materials[name]["base_outline"] = {
            "color": rgba(colors["_OutlineColor"]),
            "alpha": floats["_OutlineAlpha"],
            "glow": floats["_OutlineGlow"],
            "pixel_width": floats["_OutlinePixelWidth"],
        }
        shader = material.read().m_Shader.read()
        bytecode, parameters, proof = extract(shader, keywords)
        (audit / f"{name}.dxbc").write_bytes(bytecode)
        (audit / f"{name}.params").write_bytes(parameters)
        manifest[shader.m_ParsedForm.m_Name].setdefault("outline_programs", {})[name] = proof
    code = (decompiled / "Enemy.StateMachine/EnemyStateMachine.cs").read_text(encoding="utf8")
    match = re.search(
        r"float endValue = \(doFade \? ([\d.]+)f : \(Entity.*?\? ([\d.]+)f : ([\d.]+)f", code
    )
    assert match
    evidence["outline"] = dict(zip(["selected", "in_range", "outside"], map(float, match.groups())))
    evidence["outline"]["sprite_count"] = len(keys)
    evidence["outline"]["textures"] = list(importer.texture_assets.values())
    evidence["source_sha256"]["Enemy.StateMachine/EnemyStateMachine.cs"] = hashlib.sha256(
        (decompiled / "Enemy.StateMachine/EnemyStateMachine.cs").read_bytes()
    ).hexdigest()
    for texture in importer.texture_assets.values():
        options = (output / texture["path"]).with_suffix(".png.import")
        if options.exists():
            options.write_text(
                options.read_text(encoding="utf8").replace(
                    "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                ),
                encoding="utf8",
            )
    for filename, data in [
        ("weakpoints.json", evidence),
        ("materials.json", materials),
        ("sprites.json", sprites),
    ]:
        dump(output / filename, data)
    (output / "material_programs.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )
    print("Original outline meshes:", len(keys), "textures:", len(importer.texture_assets))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
        Path("tmp/art-direction/outline-audit"),
    )
