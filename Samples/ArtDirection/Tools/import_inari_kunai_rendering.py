"""Recover ShurikenObject's actual renderer, sprite, prefab scale and material."""

import argparse
import hashlib
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump, rgba
from import_inari_arrow import save_pixels
from extract_inari_uv_programs import extract


def export(source, output):
    env = UnityPy.load(str(source / "sharedassets1.assets"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    kunai = next(
        o
        for o in env.objects
        if o.type.name == "MonoBehaviour"
        and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "ShurikenObject"
    )
    state = kunai.read_typetree()
    root_go = state["m_GameObject"]["m_PathID"]
    transform = next(
        o.read_typetree()
        for o in env.objects
        if o.type.name == "Transform" and o.read_typetree()["m_GameObject"]["m_PathID"] == root_go
    )
    renderer = PPtr(**state["spriteRenderer"], assetsfile=kunai.assets_file).deref()
    data = renderer.read_typetree()
    assert data["m_GameObject"]["m_PathID"] == root_go
    sprite_pointer = PPtr(**data["m_Sprite"], assetsfile=renderer.assets_file)
    sprite = sprite_pointer.read()
    directory = output / "Projectiles"
    directory.mkdir(parents=True, exist_ok=True)
    info = save_pixels(sprite.image, directory, "kunai.png")
    info["path"] = "Projectiles/" + info["path"]
    info["ppu"] = sprite.m_PixelsToUnits
    info["name"] = sprite.m_Name
    info["source_id"] = str(sprite_pointer.path_id)
    offset = sprite.m_RD.textureRectOffset
    info["offset"] = [
        offset.x - sprite.m_Pivot.x * sprite.m_Rect.width,
        sprite.m_Pivot.y * sprite.m_Rect.height - offset.y - info["size"][1],
    ]
    material_pointer = PPtr(**data["m_Materials"][0], assetsfile=renderer.assets_file)
    material = material_pointer.deref()
    raw = material.read_typetree()
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.materials, importer.material_details, importer.texture_assets = {}, {}, {}
    importer.material(material_pointer)
    material_info = importer.material_details[raw["m_Name"]]
    assert material_info["lighting_mask"] is not None
    code, params, proof = extract(material.read().m_Shader.read(), set(raw["m_ValidKeywords"]))
    audit = Path("tmp/art-direction/kunai-rendering")
    audit.mkdir(parents=True, exist_ok=True)
    (audit / "Mat_Shuriken.dxbc").write_bytes(code)
    (audit / "Mat_Shuriken.params").write_bytes(params)
    sources = {
        "sharedassets1.assets",
        "Managed/Assembly-CSharp.dll",
        material.assets_file.name,
        material.read().m_Shader.deref().assets_file.name,
    }
    dump(
        output / "kunai_rendering.json",
        {
            "renderer_id": str(renderer.path_id),
            "sprite": info,
            "material": material_info,
            "prefab_scale": [transform["m_LocalScale"][axis] for axis in "xy"],
            "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
            "layer_id": data["m_SortingLayerID"],
            "color": rgba(data["m_Color"]),
            "flip": [data["m_FlipX"], data["m_FlipY"]],
            "filter": sprite.m_RD.texture.read().m_TextureSettings.m_FilterMode,
            "bright_duration": state["brightDuration"],
            "fade_duration": state["fadeOutDuration"],
            "program": proof,
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                for name in sorted(sources)
            },
        },
    )
    print(
        "Native kunai", sprite.m_Name, info["source_id"], "size", info["size"], "ppu", info["ppu"]
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
