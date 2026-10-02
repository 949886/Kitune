"""Recover tilted sprite depth gradients without rebuilding scene/gameplay data."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import PIXELS_PER_UNIT, TypeTreeGenerator, UnityPy, dump
from unity_scene_spatial import SceneSpatial


def export(source, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    proof = {"pixels_per_unit": PIXELS_PER_UNIT, "levels": {}}
    for path in sorted(output.glob("level*.json")):
        scene = json.loads(path.read_text(encoding="utf8"))
        environment = UnityPy.load(str(source / path.stem))
        environment.typetree_generator = generator
        objects = list(environment.objects)
        transforms = {
            obj.path_id: obj.read_typetree()
            for obj in objects
            if obj.type.name in ("Transform", "RectTransform")
        }
        by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}
        spatial = SceneSpatial(objects, transforms)
        selected = {}
        for item in scene["sprites"]:
            if item["spatial"]["parallel"]:
                continue
            tid = by_go[item["go"]]
            recovered = spatial.sprite_plane(tid, PIXELS_PER_UNIT)
            previous = {k: v for k, v in item["spatial"].items() if k != "depth_gradient"}
            assert previous == {k: v for k, v in recovered.items() if k != "depth_gradient"}
            item["spatial"] = recovered
            # Keep the original Unity-unit matrix for independent ray/plane GPU
            # probes, before Y inversion or division by pixels-per-unit.
            selected[str(item["go"])] = spatial.world.matrix(tid)
        assert not any(str(track.get("go")) in selected for track in scene["animations"])
        proof["levels"][path.stem] = {
            "source_sha256": hashlib.sha256((source / path.stem).read_bytes()).hexdigest(),
            "world_matrices": selected,
        }
        dump(path, scene)
        print(path.stem, "tilted renderers:", len(selected))
    dump(output / "tilted_planes.json", proof)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
