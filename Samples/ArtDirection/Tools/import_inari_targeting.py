"""Record source constants for the player's weak-point and gamepad target queries."""

import argparse
import hashlib
import re
from pathlib import Path

from import_inari import dump


def export(decompiled, output):
    player = (decompiled / "PlayerStateMachine.cs").read_text(encoding="utf8")
    inputs = (decompiled / "PlayerInputController.cs").read_text(encoding="utf8")
    layers = (decompiled / "DHUtil.LayerMask/GetCollisionLayerMask.cs").read_text(encoding="utf8")
    capacities = re.findall(r"Collider2D\[\] _colliderBuffer\d? = new Collider2D\[(\d+)\]", player)
    assert len(capacities) == 2 and len(set(capacities)) == 1
    deadzone = re.search(r"IsRightStickPressed = direction.magnitude > ([\d.]+)f", inputs)
    sight = re.search(r"IgnorePlatform = (.*?);", layers).group(1)
    names = [
        "PlayerStateMachine.cs",
        "PlayerInputController.cs",
        "InputManager.cs",
        "InGameEntity.cs",
        "DHUtil.LayerMask/GetCollisionLayerMask.cs",
    ]
    dump(
        output,
        {
            "query_capacity": int(capacities[0]),
            "right_stick_deadzone": float(deadzone.group(1)),
            "sight_layers": re.findall(r"GetLayerMasks\.(\w+)", sight),
            "source_sha256": {
                name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest() for name in names
            },
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/targeting.json",
    )
