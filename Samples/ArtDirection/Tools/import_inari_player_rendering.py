"""Recover the persistent player's actual GFX renderer and material variant."""

import argparse
import hashlib
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump, rgba
from extract_inari_uv_programs import extract


def export(source, output):
    env = UnityPy.load(str(source / "level1"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    player = next(
        o
        for o in env.objects
        if o.type.name == "MonoBehaviour"
        and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "PlayerStateMachine"
    )
    state = player.read_typetree()
    gfx = PPtr(**state["GFX"], assetsfile=player.assets_file).deref()
    go = (
        gfx.path_id
        if gfx.type.name == "GameObject"
        else gfx.read_typetree()["m_GameObject"]["m_PathID"]
    )
    renderer = next(
        o
        for o in env.objects
        if o.type.name == "SpriteRenderer" and o.read_typetree()["m_GameObject"]["m_PathID"] == go
    )
    data = renderer.read_typetree()
    pointer = PPtr(**data["m_Materials"][0], assetsfile=renderer.assets_file)
    material = pointer.deref()
    raw = material.read_typetree()
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.materials, importer.material_details, importer.texture_assets = {}, {}, {}
    importer.material(pointer)
    info = importer.material_details[raw["m_Name"]]
    saved = raw["m_SavedProperties"]
    floats = dict(saved["m_Floats"])
    colors = dict(saved["m_Colors"])
    info["floats"] = {
        name: value for name, value in floats.items() if name.startswith("_InnerOutline")
    }
    info["inner_outline_color"] = rgba(colors["_InnerOutlineColor"])
    # Keep the actual mask provenance even when its uniform pixels reduce to a constant.
    textures = dict(saved["m_TexEnvs"])
    mask_pointer = PPtr(**textures["_MaskTex"]["m_Texture"], assetsfile=material.assets_file)
    mask = importer.texture_asset(mask_pointer)
    assert info["lighting_mask"] is not None, "A spatial mask needs original atlas coordinates"
    code, parameters, proof = extract(material.read().m_Shader.read(), set(raw["m_ValidKeywords"]))
    audit = Path("tmp/art-direction/player-rendering")
    audit.mkdir(parents=True, exist_ok=True)
    (audit / "Player.dxbc").write_bytes(code)
    (audit / "Player.params").write_bytes(parameters)
    source_files = {
        "level1",
        "sharedassets1.assets",
        "Managed/Assembly-CSharp.dll",
        material.assets_file.name,
        mask_pointer.deref().assets_file.name,
        material.read().m_Shader.deref().assets_file.name,
    }
    result = {
        "material_source_file": material.assets_file.name,
        "renderer_id": renderer.path_id,
        "gfx_id": go,
        "sort": [data["m_SortingLayer"], data["m_SortingOrder"]],
        "layer_id": data["m_SortingLayerID"],
        "color": rgba(data["m_Color"]),
        "flip": [data["m_FlipX"], data["m_FlipY"]],
        "material": info,
        "material_id": str(material.path_id),
        "mask": mask,
        "program": proof,
        "source_sha256": {
            name: hashlib.sha256((source / name).read_bytes()).hexdigest()
            for name in sorted(source_files)
        },
    }
    dump(output / "player_rendering.json", result)
    print(
        "Player renderer",
        renderer.path_id,
        "mask",
        info["lighting_mask"],
        "program",
        proof["program_index"],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
