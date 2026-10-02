"""Export native nine-slice borders without repacking or modifying sprite pixels."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy
from import_inari_water import pointer


def export(source, output):
    sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    profiles = json.loads(
        (Path(__file__).resolve().parents[1] / "Profiles/levels.json").read_text(encoding="utf8")
    )
    scenes = sorted({Path(p["scene_data"]).stem for p in profiles if p["kind"] == "original_2d"})
    result = {"sprites": {}, "scenes": {}, "source_files": {}}
    files = set(scenes)
    for scene in scenes:
        environment = UnityPy.load(str(source / scene))
        renderers = []
        for obj in environment.objects:
            if obj.type.name != "SpriteRenderer":
                continue
            data = obj.read_typetree()
            if data["m_DrawMode"] == 0 or not data["m_Sprite"]["m_PathID"]:
                continue
            # The selected source scenes use Continuous exclusively. Do not silently
            # apply its partial-tile rule to a future Adaptive renderer.
            assert data["m_SpriteTileMode"] == 0
            native = pointer(obj, data["m_Sprite"])
            sprite = native.read()
            key = f"{Path(native.assets_file.name).stem}_{native.path_id}"
            if key not in sprites:
                continue  # Disabled/collision-only source renderers were not exported.
            info = sprites[key]
            width, height = sprite.m_Rect.width, sprite.m_Rect.height
            offset = sprite.m_RD.textureRectOffset
            trim = [offset.x, height - offset.y - info["size"][1], *info["size"]]
            pivot = [sprite.m_Pivot.x, 1.0 - sprite.m_Pivot.y]
            expected = [trim[0] - pivot[0] * width, trim[1] - pivot[1] * height]
            assert all(abs(a - b) < 0.001 for a, b in zip(expected, info["offset"]))
            border = sprite.m_Border
            result["sprites"][key] = {
                "size": [width, height],
                "pivot": pivot,
                "border": [border.x, border.w, border.z, border.y],
                "trim": trim,
            }
            renderers.append(
                {
                    "go": data["m_GameObject"]["m_PathID"],
                    "sprite": key,
                    "mode": data["m_DrawMode"],
                    "tile_mode": data["m_SpriteTileMode"],
                }
            )
            files.add(native.assets_file.name)
        result["scenes"][scene] = renderers
    result["source_files"] = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in sorted(files)
    }
    (output / "sprite_slicing.json").write_text(
        json.dumps(result, separators=(",", ":")) + "\n", encoding="utf8"
    )
    print(f"Exported {len(result['sprites'])} native slice definitions from {len(scenes)} scenes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / "Original/INARI"
    )
    args = parser.parse_args()
    export(args.data_directory, args.output)
