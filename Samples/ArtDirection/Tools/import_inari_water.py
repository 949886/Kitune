"""Export the shrine water camera, renderer feature, shader bindings and native mips."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator
from UnityPy.classes import PPtr
from UnityPy.export.Texture2DConverter import parse_image_data
from extract_inari_uv_programs import extract


def pointer(owner, value):
    return PPtr(**value, assetsfile=owner.assets_file).deref()


def component(objects, class_name):
    return next(
        obj
        for obj in objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == class_name
    )


def export(source, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    scene = UnityPy.load(str(source / "level25"))
    scene.typetree_generator = generator
    objects = list(scene.objects)
    controller = component(objects, "WaterCameraController")
    controller_data = controller.read_typetree()
    camera = next(
        obj
        for obj in objects
        if obj.type.name == "Camera"
        and obj.read_typetree()["m_GameObject"] == controller_data["m_GameObject"]
    )
    camera_data = camera.read_typetree()
    target = pointer(camera, camera_data["m_TargetTexture"]).read_typetree()

    globals_env = UnityPy.load(str(source / "globalgamemanagers"))
    globals_env.typetree_generator = generator
    graphics = next(obj for obj in globals_env.objects if obj.type.name == "GraphicsSettings")
    pipeline = pointer(graphics, graphics.read_typetree()["m_CustomRenderPipeline"])
    pipeline_data = pipeline.read_typetree()
    renderer = pointer(
        pipeline, pipeline_data["m_RendererDataList"][pipeline_data["m_DefaultRendererIndex"]]
    )
    feature = component(
        [pointer(renderer, ref) for ref in renderer.read_typetree()["m_RendererFeatures"]],
        "WaterTextureFeature",
    )

    material = None
    for obj in objects:
        if obj.type.name != "SpriteRenderer":
            continue
        for ref in obj.read_typetree()["m_Materials"]:
            if ref["m_PathID"]:
                candidate = pointer(obj, ref)
                if candidate.peek_name() == "Mat_Water":
                    material = candidate
                    break
        if material:
            break
    assert material is not None, "Shrine water material missing"
    material_data = material.read_typetree()
    floats = dict(material_data["m_SavedProperties"]["m_Floats"])
    textures = dict(material_data["m_SavedProperties"]["m_TexEnvs"])
    shader = material.read().m_Shader.read()
    _, _, proof = extract(shader, set(material_data["m_ValidKeywords"]))
    shader_pass = shader.object_reader.read_typetree()["m_ParsedForm"]["m_SubShaders"][0][
        "m_Passes"
    ][0]
    names = {index: name for name, index in shader_pass["m_NameIndices"]}
    common = shader_pass["progFragment"]["m_CommonParameters"]
    proof["bindings"] = {
        names[buffer["m_NameIndex"]]: {
            names[param["m_NameIndex"]]: param["m_Index"] for param in buffer["m_VectorParams"]
        }
        for buffer in common["m_ConstantBuffers"]
    }
    texture_name = next(
        names[t["m_NameIndex"]] for t in common["m_TextureParams"] if t["m_Index"] == 0
    )
    normal_ref = pointer(material, textures[texture_name]["m_Texture"])
    normal = normal_ref.read()
    assert normal.m_TextureFormat == 12 and normal.m_ColorSpace == 0
    raw = normal.get_image_data()
    directory = output / "Textures/WaterNormal"
    directory.mkdir(parents=True, exist_ok=True)
    width, height, offset = normal.m_Width, normal.m_Height, 0
    mips = []
    for level in range(normal.m_MipCount):
        size = ((width + 3) // 4) * ((height + 3) // 4) * 16
        packed = raw[offset : offset + size]
        image = parse_image_data(
            packed,
            width,
            height,
            normal.m_TextureFormat,
            normal_ref.version,
            normal_ref.platform,
            normal.m_PlatformBlob,
        )
        filename = f"Textures/WaterNormal/mip_{level}.png"
        image.save(output / filename)
        import_path = (output / filename).with_suffix(".png.import")
        if import_path.exists():
            # Keep the source packed-normal channels and authored mip pixels.
            # Resource loading then works in packaged games as well as the editor.
            options = import_path.read_text(encoding="utf8")
            for old, new in (
                ("process/fix_alpha_border=true", "process/fix_alpha_border=false"),
                ("compress/normal_map=0", "compress/normal_map=2"),
                ("mipmaps/generate=true", "mipmaps/generate=false"),
            ):
                options = options.replace(old, new)
            import_path.write_text(options, encoding="utf8")
        mips.append(
            {
                "path": filename,
                "width": width,
                "height": height,
                "rgba_sha256": hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest(),
            }
        )
        offset += size
        width, height = max(1, width // 2), max(1, height // 2)
    assert offset == len(raw), "Unexpected source DXT5 mip layout"
    result = {
        "scene": "level25",
        "pixels_per_unit": 16,
        "camera": {
            "fov": camera_data["field of view"],
            "near": camera_data["near clip plane"],
            "far": camera_data["far clip plane"],
            "offset": controller_data["offset"],
            "target_size": [target["m_Width"], target["m_Height"]],
            "projection_note": "Perspective aspect derives from Camera.targetTexture (1x1), not the feature's later 1920x1080 color target.",
        },
        "feature": feature.read_typetree()["settings"],
        "material": {
            key: floats[key] for key in ("_Speed", "_Strength", "_Tilling", "_SurfaceSpeed")
        },
        "normal": {
            "name": normal.m_Name,
            "color_space": normal.m_ColorSpace,
            "format": normal.m_TextureFormat,
            "mips": mips,
            "settings": normal_ref.read_typetree()["m_TextureSettings"],
        },
        "program": proof,
        "source_files": {
            name: hashlib.sha256((source / name).read_bytes()).hexdigest()
            for name in (
                "level25",
                "sharedassets25.assets",
                "sharedassets25.assets.resS",
                "globalgamemanagers.assets",
                "Managed/Assembly-CSharp.dll",
            )
        },
    }
    (output / "water.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(f"Exported water settings and {len(mips)} original normal mips")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
