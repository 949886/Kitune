"""Recover the original shockwave's scene-copy boundary and age-driven shader."""

import argparse
import hashlib
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, dump
from extract_inari_uv_programs import extract


def export(source, urp_sources, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "globalgamemanagers"), str(source / "level15"))
    env.typetree_generator = generator
    graphics = next(obj for obj in env.objects if obj.type.name == "GraphicsSettings")
    pipeline = PPtr(
        **graphics.read_typetree()["m_CustomRenderPipeline"], assetsfile=graphics.assets_file
    ).deref()
    config = pipeline.read_typetree()
    renderer = PPtr(
        **config["m_RendererDataList"][config["m_DefaultRendererIndex"]],
        assetsfile=pipeline.assets_file
    ).deref()
    config = renderer.read_typetree()
    bound = config["m_CameraSortingLayersTextureBound"]
    values = set()
    for obj in env.objects:
        if obj.type.name in ("SpriteRenderer", "TilemapRenderer"):
            data = obj.read_typetree()
            if data["m_SortingLayerID"] == bound:
                values.add(data["m_SortingLayer"])
    assert len(values) == 1
    bound_value = values.pop()
    tags = next(obj.read_typetree() for obj in env.objects if obj.type.name == "TagManager")
    name = next(layer["name"] for layer in tags["m_SortingLayers"] if layer["uniqueID"] == bound)
    bundle_root = source / "StreamingAssets/aa/StandaloneWindows64"
    bundles = [
        next(bundle_root.glob(pattern))
        for pattern in [
            "defaultlocalgroup*.bundle",
            "shaderassets*.bundle",
            "*unitybuiltinshaders*.bundle",
        ]
    ]
    env = UnityPy.load(*map(str, bundles))
    material = next(
        obj for obj in env.objects if obj.type.name == "Material" and obj.peek_name() == "ShockWave"
    )
    data = material.read_typetree()
    floats = dict(data["m_SavedProperties"]["m_Floats"])
    shader = material.read().m_Shader.read()
    render_pass = shader.object_reader.read_typetree()["m_ParsedForm"]["m_SubShaders"][0][
        "m_Passes"
    ][0]
    names = dict(render_pass["m_NameIndices"])
    texture_param = render_pass["progFragment"]["m_CommonParameters"]["m_TextureParams"][0]
    assert texture_param["m_NameIndex"] == names["_CameraSortingLayerTexture"]
    evidence = {
        "capture_enabled": bool(config["m_UseCameraSortingLayersTexture"]),
        "capture_layer_id": bound,
        "capture_layer": name,
        "capture_layer_value": bound_value,
        "capture_order_before": [bound_value + 1],
        "downsampling": config["m_CameraSortingLayerDownsamplingMethod"],
        "distortion_strength": floats["_DistortionStrength"],
        "size": floats["_Size"],
        "age_stream": 21,
        "texture": "_CameraSortingLayerTexture",
        "pass": render_pass["m_State"]["m_Name"],
        "blend": render_pass["m_State"]["rtBlend0"],
        "programs": {},
        "source_sha256": {},
    }
    audit = Path(__file__).resolve().parents[3] / "tmp/art-direction/shockwave"
    audit.mkdir(parents=True, exist_ok=True)
    for stage in ["fragment", "vertex"]:
        code, params, proof = extract(shader, set(), stage)
        (audit / (stage + ".dxbc")).write_bytes(code)
        (audit / (stage + ".params")).write_bytes(params)
        evidence["programs"][stage] = proof
    files = bundles + [
        source / "globalgamemanagers",
        source / "level15",
        source / "Managed/Unity.RenderPipelines.Universal.Runtime.dll",
        source / "Managed/UnityEngine.ParticleSystemModule.dll",
    ]
    files += [urp_sources / name for name in ["Render2DLightingPass.cs", "RendererLighting.cs"]]
    for path in files:
        evidence["source_sha256"][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    assert evidence["capture_enabled"] and evidence["downsampling"] == 0
    dump(output / "shockwave.json", evidence)
    print(
        "Native shockwave: capture through",
        name,
        "value",
        bound_value,
        "strength",
        floats["_DistortionStrength"],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("urp_sources", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.urp_sources,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
