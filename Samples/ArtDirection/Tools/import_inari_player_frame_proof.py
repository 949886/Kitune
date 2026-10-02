"""Read first-frame pixel evidence for the idle/spawn visual-isolation fixtures."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy, dump


def export(source, output):
    clips = json.loads((output / "player.json").read_text(encoding="utf8"))
    files, evidence = {}, {}
    for clip_name in ("spawn", "idle"):
        key = clips[clip_name]["frames"][0][1]
        filename, path_id = key.rsplit("_", 1)
        filename += ".assets"
        if filename not in files:
            files[filename] = {
                obj.path_id: obj for obj in UnityPy.load(str(source / filename)).objects
            }
        sprite = files[filename][int(path_id)].read()
        pixels = sprite.image.convert("RGBA")
        rgba = pixels.tobytes()
        visible = bytearray(rgba)
        # Old study atlases retain Godot's alpha-border option. Its transparent
        # RGB may differ, so verify both the raw PNG and rendered visible pixels.
        for index in range(0, len(visible), 4):
            if visible[index + 3] == 0:
                visible[index : index + 3] = b"\0\0\0"
        evidence[clip_name] = {
            "sprite": key,
            "name": sprite.m_Name,
            "size": list(pixels.size),
            "rgba_sha256": hashlib.sha256(rgba).hexdigest(),
            "visible_rgba_sha256": hashlib.sha256(visible).hexdigest(),
            "source_file": filename,
            "source_id": int(path_id),
            "source_file_sha256": hashlib.sha256((source / filename).read_bytes()).hexdigest(),
        }
    dump(output / "player_frame_proof.json", evidence)
    print("Source first-frame proofs:", ", ".join(evidence))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
