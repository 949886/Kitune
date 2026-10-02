"""Export the shipped UV pixel programs and their parameter layouts for inspection.

The game is read-only. Bytecode goes to the ignored audit directory; only hashes
and source identifiers are added to the study's material provenance manifest.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tmp/art-direction/pydeps"))
import UnityPy
from UnityPy.classes import PPtr
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader


def extract(shader, keywords, stage="fragment"):
    parsed = shader.object_reader.read_typetree()["m_ParsedForm"]
    stage_key, gpu_type = {"fragment": ("progFragment", 17), "vertex": ("progVertex", 15)}[stage]
    fragment = parsed["m_SubShaders"][0]["m_Passes"][0][stage_key]
    names = parsed["m_KeywordNames"]
    candidate = None
    for group_index, group in enumerate(fragment["m_PlayerSubPrograms"]):
        for index, program in enumerate(group):
            actual = {
                names[k]
                for k in program["m_KeywordIndices"]
                if not names[k].startswith("USE_SHAPE_LIGHT_TYPE_")
            }
            if actual == keywords and program["m_GpuProgramType"] == gpu_type:
                candidate = program
                parameter_index = fragment["m_ParameterBlobIndices"][group_index][index]
                break
        if candidate:
            break
    if candidate is None:
        raise ValueError(f"D3D11 pixel variant not found: {sorted(keywords)}")

    platform_index = list(shader.platforms).index(4)
    blob = bytes(shader.compressedBlob)
    blocks = [
        CompressionHelper.decompress_lz4(blob[offset : offset + compressed], size)
        for offset, compressed, size in zip(
            shader.offsets[platform_index],
            shader.compressedLengths[platform_index],
            shader.decompressedLengths[platform_index],
        )
    ]
    reader = EndianBinaryReader(blocks[0], endian="<")
    entries = [
        (reader.read_int(), reader.read_int(), reader.read_int()) for _ in range(reader.read_int())
    ]

    def entry(index):
        offset, size, segment = entries[index]
        return blocks[segment][offset : offset + size]

    program = entry(candidate["m_BlobIndex"])
    start = program.index(b"DXBC")
    size = int.from_bytes(program[start + 24 : start + 28], "little")
    bytecode = program[start : start + size]
    parameters = entry(parameter_index)
    return (
        bytecode,
        parameters,
        {
            "program_index": candidate["m_BlobIndex"],
            "parameter_index": parameter_index,
            "keywords": sorted(keywords),
            "program_sha256": hashlib.sha256(bytecode).hexdigest(),
            "parameters_sha256": hashlib.sha256(parameters).hexdigest(),
        },
    )


def main(source, output, study):
    known = json.loads((study / "Original/INARI/materials.json").read_text(encoding="utf8"))
    targets = {name for name, material in known.items() if material.get("uv_effects")}
    environment = UnityPy.load(str(source / "level25"))
    manifest_path = study / "Original/INARI/material_programs.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf8"))
    visited = set()
    output.mkdir(parents=True, exist_ok=True)
    for obj in environment.objects:
        if obj.type.name != "SpriteRenderer":
            continue
        for reference in obj.read_typetree()["m_Materials"]:
            if not reference["m_PathID"]:
                continue
            material = PPtr(**reference, assetsfile=obj.assets_file).deref()
            name = material.peek_name()
            if name not in targets or name in visited:
                continue
            visited.add(name)
            data = material.read_typetree()
            shader = material.read().m_Shader.read()
            bytecode, parameters, proof = extract(shader, set(data["m_ValidKeywords"]))
            (output / f"{name}.dxbc").write_bytes(bytecode)
            (output / f"{name}.params").write_bytes(parameters)
            shader_name = shader.m_ParsedForm.m_Name
            source_name = shader.object_reader.assets_file.name
            shader_proof = manifest.setdefault(shader_name, {})
            shader_proof.update(
                {
                    "source_file": source_name,
                    "source_sha256": hashlib.sha256(
                        (source / source_name).read_bytes()
                    ).hexdigest(),
                    "shader_id": shader.object_reader.path_id,
                }
            )
            shader_proof.setdefault("uv_programs", {})[name] = proof
            print(
                f"{name}: pixel program {proof['program_index']}, parameters {proof['parameter_index']}"
            )
    if visited != targets:
        raise ValueError(f"Missing source materials: {targets - visited}")
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--output", type=Path, default=Path("tmp/art-direction/uv-programs"))
    args = parser.parse_args()
    main(args.data_directory, args.output, Path(__file__).resolve().parents[1])
