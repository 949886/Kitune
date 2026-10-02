"""Refresh navigation cell types from the original serialized map, without rebuilding art."""

import argparse
import json
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator


def export(source, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    for path in sorted(output.glob("level*.json")):
        scene = json.loads(path.read_text(encoding="utf8"))
        navigation = scene.get("navigation", {})
        if not navigation:
            continue
        env = UnityPy.load(str(source / navigation["source_file"]))
        env.typetree_generator = generator
        obj = next(obj for obj in env.objects if obj.path_id == navigation["source_id"])
        cells = obj.read_typetree()["GroundTileMapArea"]
        pairs = list(zip(cells["keys"], cells["values"]))
        ground = [[cell["x"], cell["y"]] for cell, kind in pairs if kind == 0]
        assert ground == navigation["ground"], "The source map changed; rebuild the scene first"
        navigation["walls"] = [[cell["x"], cell["y"]] for cell, kind in pairs if kind == 1]
        # NearestEnemies searches all registered non-wall cells, including air.
        navigation["non_wall"] = [[cell["x"], cell["y"]] for cell, kind in pairs if kind != 1]
        path.write_text(json.dumps(scene, separators=(",", ":")) + "\n", encoding="utf8")
        print(path.name, "walls", len(navigation["walls"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
