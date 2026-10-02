"""Extract the installed player's gamepad air-aim timing rules."""

import argparse
import hashlib
import re
from pathlib import Path

from import_inari import dump


def export(source, output):
    player = (source / "PlayerStateMachine.cs").read_text(encoding="utf8")
    begin = player.index("private void CheckAiringInGamePad()")
    end = player.index("private void ResetRightStickDirection", begin)
    method = player[begin:end]
    scales = re.findall(r"SetTimeScale\(([\d.]+)f\)", method)
    assert len(scales) == 3 and scales[0] == scales[2]
    assert "base.TimeScale == 0f" in method
    assert "!collisionInfo.climbingWall && !collisionInfo.climbingCeil" in method
    flags = (source / "DHUtil/PlayerFlags.cs").read_text(encoding="utf8")
    air_types = re.findall(r"PlayerCollisionType\.(\w+),\s*PlayerPhysicsFlags\.Air", flags)
    assert air_types
    files = [
        "PlayerStateMachine.cs",
        "PlayerCollision2D.cs",
        "PlayerDeadState.cs",
        "DHUtil/PlayerFlags.cs",
        "TimeManager.cs",
        "CustomCoroutineManager.cs",
        "Enemy.StateMachine/EnemyStateMachine.cs",
        "EnemyCollision.cs",
        "RaycastCollision2D.cs",
    ]
    dump(
        output,
        {
            "air_scale": float(scales[1]),
            "normal_scale": float(scales[0]),
            "air_collision_types": air_types,
            "excluded_state": re.search(
                r"CurrentStateType == PlayerStateType\.(\w+)", method
            ).group(1),
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files
            },
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/aim_time.json",
    )
