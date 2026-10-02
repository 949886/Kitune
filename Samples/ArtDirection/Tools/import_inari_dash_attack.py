"""Add the three player clips referenced by PlayerDashAttackState without repacking."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import Importer, UnityPy, dump


def export(source, decompiled, output):
    importer = Importer.__new__(Importer)
    importer.source, importer.output = source, output
    importer.sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    importer.images = {}
    importer.player()
    clips = json.loads((output / "player.json").read_text(encoding="utf8"))
    selected = {
        name: clips[name] for name in ["weak_dash_ready", "weak_dash_idle", "weak_dash_fall"]
    }
    wanted = {frame[1] for clip in selected.values() for frame in clip["frames"]}
    objects = {
        obj.path_id: obj for obj in UnityPy.load(str(source / "sharedassets1.assets")).objects
    }
    evidence = {"sprites": {}, "clips": selected, "source_sha256": {}}
    physics = next(
        obj.read_typetree()
        for obj in UnityPy.load(str(source / "globalgamemanagers")).objects
        if obj.type.name == "Physics2DSettings"
    )
    evidence["queries_start_in_colliders"] = physics["m_QueriesStartInColliders"]
    assert evidence["queries_start_in_colliders"]
    for key in sorted(wanted):
        pixels = objects[int(key.rsplit("_", 1)[1])].read().image.convert("RGBA")
        info = importer.sprites[key]
        info["path"] = "Sprites/" + key + ".png"
        info["region"] = [0, 0, *pixels.size]
        path = output / info["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        pixels.save(path)
        evidence["sprites"][key] = hashlib.sha256(pixels.tobytes()).hexdigest()
    for name in [
        "PlayerDashAttackState.cs",
        "PlayerStateMachine.cs",
        "EnemyCollision.cs",
        "RaycastCollision2D.cs",
        "DHUtil.LayerMask/GetCollisionLayerMask.cs",
    ]:
        evidence["source_sha256"][name] = hashlib.sha256(
            (decompiled / name).read_bytes()
        ).hexdigest()
    evidence["source_sha256"]["sharedassets1.assets"] = hashlib.sha256(
        (source / "sharedassets1.assets").read_bytes()
    ).hexdigest()
    dump(output / "sprites.json", importer.sprites)
    dump(output / "dash_attack.json", evidence)
    print("Native weak dash frames:", len(wanted))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
