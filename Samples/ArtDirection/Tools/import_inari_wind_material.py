"""Recover wind stations' color replacement uniforms and compiled shader provenance."""

import argparse
import hashlib
import json
import struct
from pathlib import Path

from import_inari import UnityPy, dump, rgba
from extract_inari_uv_programs import extract


def export(source, output):
    triggers = json.loads((output / "wind_buff.json").read_text(encoding="utf8"))
    materials = json.loads((output / "materials.json").read_text(encoding="utf8"))
    recovered = {}
    for level, entries in triggers["levels"].items():
        if not entries:
            continue
        env = UnityPy.load(str(source / level))
        objects = {obj.path_id: obj for obj in env.objects}
        for entry in entries:
            animator = objects[entry["animator_id"]].read()
            renderer = next(
                obj.read()
                for obj in env.objects
                if obj.type.name == "SpriteRenderer"
                and obj.read().m_GameObject.path_id == animator.m_GameObject.path_id
            )
            material = renderer.m_Materials[0].read()
            if material.m_Name in recovered:
                continue
            raw = material.object_reader.read_typetree()
            assert set(raw["m_ValidKeywords"]) == {"CHANGECOLOR_ON", "GLOW_ON"}
            code, parameters, proof = extract(material.m_Shader.read(), set(raw["m_ValidKeywords"]))
            # Parameter records end in a byte offset into cb0. Verify the disassembly mapping.
            offsets = {
                "_ColorChangeNewCol": 144,
                "_ColorChangeTarget": 160,
                "_ColorChangeTolerance": 176,
                "_ColorChangeLuminosity": 180,
            }
            for name, offset in offsets.items():
                end = parameters.index(name.encode()) + len(name)
                aligned = (end + 3) & ~3
                assert struct.unpack_from("<I", parameters, aligned + 20)[0] == offset
            saved = raw["m_SavedProperties"]
            floats, colors = dict(saved["m_Floats"]), dict(saved["m_Colors"])
            settings = {
                "target": rgba(colors["_ColorChangeTarget"]),
                "new_color": rgba(colors["_ColorChangeNewCol"]),
                "tolerance": floats["_ColorChangeTolerance"],
                "luminosity": floats["_ColorChangeLuminosity"],
            }
            materials[material.m_Name]["color_change"] = settings
            recovered[material.m_Name] = {
                "program": proof,
                "constant_buffer_offsets": offsets,
                "material_id": str(material.object_reader.path_id),
                "source_sha256": {
                    name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                    for name in sorted(
                        {
                            level,
                            material.object_reader.assets_file.name,
                            material.m_Shader.deref().assets_file.name,
                        }
                    )
                },
            }
            audit = Path("tmp/art-direction/wind-buff-audit")
            audit.mkdir(parents=True, exist_ok=True)
            (audit / (material.m_Name + ".dxbc")).write_bytes(code)
            (audit / (material.m_Name + ".params")).write_bytes(parameters)
    assert recovered
    dump(output / "materials.json", materials)
    dump(output / "wind_material.json", recovered)
    print("Recovered native wind materials:", list(recovered))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
