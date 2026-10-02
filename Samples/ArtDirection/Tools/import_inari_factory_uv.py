"""Recover factory clouds, station distortion and wind-driven fog from native shader programs."""

import argparse
import hashlib
import json
import struct
from pathlib import Path

from extract_inari_uv_programs import extract
from import_inari import Importer, PIXELS_PER_UNIT, UnityPy, dump
from unity_sprite_effects import material_effects, sprite_effect_mesh

TARGETS = {"Mat_BGCLoud", "Mat_LightDistotion 1", "Mat_LightDistotion 3"}


def export(source, output):
    scene = json.loads((output / "level15.json").read_text(encoding="utf8"))
    selected = {s["go"]: s for s in scene["sprites"] if s["material"] in TARGETS}
    materials = json.loads((output / "materials.json").read_text(encoding="utf8"))
    sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    importer = Importer.__new__(Importer)
    importer.output, importer.texture_assets = output, {}
    environment = UnityPy.load(str(source / "level15"))
    manifest, meshes, visited = {}, {}, set()
    audit = Path("tmp/art-direction/factory-uv-audit")
    audit.mkdir(parents=True, exist_ok=True)
    for obj in list(environment.objects):
        if obj.type.name != "SpriteRenderer":
            continue
        renderer = obj.read()
        go = renderer.m_GameObject.path_id
        if go not in selected:
            continue
        visited.add(go)
        item = selected[go]
        material = renderer.m_Materials[0].read()
        assert material.m_Name == item["material"]
        key = item["sprite"]
        sprite = renderer.m_Sprite.read()
        if key not in meshes:
            meshes[key] = sprite_effect_mesh(importer, sprite, PIXELS_PER_UNIT)
            sprites[key]["effect_mesh"] = meshes[key]
        if renderer.m_DrawMode == 2:
            # All selected clouds are one full tile with zero borders. Preserve
            # its exact native quad; do not replace arbitrary tiled renderers.
            assert all(getattr(sprite.m_Border, axis) == 0 for axis in ("x", "y", "z", "w"))
            vertices = meshes[key]["vertices"]
            size = [max(v[i] for v in vertices) - min(v[i] for v in vertices) for i in (0, 1)]
            assert size == item["size"]
            assert len(vertices) == 4
        else:
            assert renderer.m_DrawMode == 0
        name = material.m_Name
        if name in manifest:
            continue
        raw = material.object_reader.read_typetree()
        settings = material_effects(importer, material.object_reader, raw)
        assert settings
        materials[name]["uv_effects"] = settings
        proof = {"renderers": sorted(k for k, v in selected.items() if v["material"] == name)}
        proof["material_id"] = str(material.object_reader.path_id)
        proof["shader_id"] = str(material.m_Shader.deref().path_id)
        for stage in ("fragment", "vertex"):
            code, parameters, program = extract(
                material.m_Shader.read(), set(raw["m_ValidKeywords"]), stage
            )
            proof[stage] = program
            if "WIND_ON" in raw["m_ValidKeywords"]:
                if stage == "vertex":
                    assert b"_GrassSpeed" not in parameters
                else:
                    offsets = {"_GrassSpeed": 2204, "_GrassWind": 2208, "_GrassRadialBend": 2216}
                    for key, offset in offsets.items():
                        end = parameters.index(key.encode()) + len(key)
                        aligned = (end + 3) & ~3
                        assert struct.unpack_from("<I", parameters, aligned + 20)[0] == offset
                    proof["wind_fragment_offsets"] = offsets
            (audit / (name + "_" + stage + ".dxbc")).write_bytes(code)
            (audit / (name + "_" + stage + ".params")).write_bytes(parameters)
        proof["source_sha256"] = {
            file: hashlib.sha256((source / file).read_bytes()).hexdigest()
            for file in sorted(
                {
                    "level15",
                    material.object_reader.assets_file.name,
                    material.m_Shader.deref().assets_file.name,
                }
            )
        }
        manifest[name] = proof
    assert visited == set(selected) and set(manifest) == TARGETS
    for mesh in meshes.values():
        settings = (output / mesh["texture"]["path"]).with_suffix(".png.import")
        if settings.exists():
            text = settings.read_text(encoding="utf8")
            settings.write_text(
                text.replace("process/fix_alpha_border=true", "process/fix_alpha_border=false"),
                encoding="utf8",
            )
    dump(output / "materials.json", materials)
    dump(output / "sprites.json", sprites)
    dump(output / "factory_uv.json", manifest)
    print("Recovered factory UV renderers:", len(visited))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
