"""Preserve the installed weak-point warp's original texture domain and program proof."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import Importer, UnityPy, PPtr, dump, PIXELS_PER_UNIT
from unity_sprite_effects import material_effects, sprite_effect_mesh
from extract_inari_uv_programs import extract


def export(source, output, audit):
    materials = json.loads((output / "materials.json").read_text(encoding="utf8"))
    sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    manifest_path = output / "material_programs.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf8"))
    # This incremental import needs only texture export, without rebuilding scene data.
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.texture_assets = {}
    wanted = {
        name
        for name, data in materials.items()
        if set(data["keywords"]) == {"WARP_ON", "GLOWLIGHT_ON"}
    }
    found = set()
    audit.mkdir(parents=True, exist_ok=True)
    environment = UnityPy.load(str(source / "level15"))
    for obj in environment.objects:
        if obj.type.name != "SpriteRenderer":
            continue
        renderer = obj.read_typetree()
        for reference in renderer["m_Materials"]:
            material = PPtr(**reference, assetsfile=obj.assets_file).deref()
            name = material.peek_name()
            if name not in wanted:
                continue
            data = material.read_typetree()
            sprite = PPtr(**renderer["m_Sprite"], assetsfile=obj.assets_file).read()
            key = (
                f"{Path(sprite.object_reader.assets_file.name).stem}_{sprite.object_reader.path_id}"
            )
            assert key in sprites, "Only update already imported weak-point sprites"
            sprites[key]["effect_mesh"] = sprite_effect_mesh(importer, sprite, PIXELS_PER_UNIT)
            if name in found:
                continue
            found.add(name)
            materials[name]["uv_effects"] = material_effects(importer, material, data)
            shader = material.read().m_Shader.read()
            bytecode, parameters, proof = extract(shader, set(data["m_ValidKeywords"]))
            (audit / f"{name}.dxbc").write_bytes(bytecode)
            (audit / f"{name}.params").write_bytes(parameters)
            shader_proof = manifest[shader.m_ParsedForm.m_Name]
            shader_proof.setdefault("uv_programs", {})[name] = proof
            proof["source_material_id"] = material.path_id
            proof["source_material_file"] = material.assets_file.name
            proof["source_material_file_sha256"] = hashlib.sha256(
                (source / material.assets_file.name).read_bytes()
            ).hexdigest()
            print(name, key, proof["program_index"])
    assert found == wanted and wanted, (wanted, found)
    for texture in importer.texture_assets.values():
        options = (output / texture["path"]).with_suffix(".png.import")
        if options.exists():
            options.write_text(
                options.read_text(encoding="utf8").replace(
                    "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                ),
                encoding="utf8",
            )
    dump(output / "materials.json", materials)
    dump(output / "sprites.json", sprites)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--audit", type=Path, default=Path("tmp/art-direction/warp-audit"))
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.audit)
