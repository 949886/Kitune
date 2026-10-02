"""Retain the native trail color rule and run-dust frame gates from the installed code."""

import argparse
import hashlib
import re
from pathlib import Path

from import_inari import dump


def export(source, output):
    player = (source / "PlayerStateMachine.cs").read_text(encoding="utf8")
    method = player.split("private void ControlWindBuffGfx()")[1].split(
        "public void StaminaChangeEffectRoutine"
    )[0]
    assert "BuffDurationRatio != 0f" in method
    assert "new Color(1f, 1f - num, 1f - num)" in method
    assert "MoveSpeedLevel > 0 && base.CurrentStateType == PlayerStateType.Run" in method
    frames = [
        int(value)
        for value in re.search(r"new List<int> \{ ([\d, ]+) \}", method).group(1).split(",")
    ]
    dust = (
        (source / "PlayerRunTimeEffectManager.cs")
        .read_text(encoding="utf8")
        .split("public void MakeRunDustEffect")[1]
    )
    assert "previousNormalizedTimes.TryAdd(instanceID, 1f)" in dust
    assert "num3 < num4 && num2 >= num4" in dust
    effect = re.search(r'Pop\("([^"]+)"\)', dust).group(1)
    dump(
        output,
        {
            "trail": "PlayerAmbientTrail",
            "dust": effect,
            "frames": frames,
            "previous_normalized_time": 1.0,
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                for name in ["PlayerStateMachine.cs", "PlayerRunTimeEffectManager.cs"]
            },
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/wind_trail.json",
    )
