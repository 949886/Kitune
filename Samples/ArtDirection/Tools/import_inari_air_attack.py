"""Recover the shipped JumpAttack movement, facing, sound and exit contract."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

from import_inari import dump


def export(source, output, ilspy):
    assembly = source / "Managed/Assembly-CSharp.dll"
    code = {
        name: subprocess.check_output([str(ilspy), "-t", name, str(assembly)], encoding="utf8")
        for name in (
            "PlayerJumpAttackPattern",
            "PlayerStateMachine",
            "PlayerInputController",
            "PlayerCollision2D",
            "DHUtil.PlayerFlags",
            "PlayerStateFlags",
        )
    }
    pattern = code["PlayerJumpAttackPattern"]
    for expression in (
        "faceDir = stateMachine.GetFaceDirection();",
        "stateMachine.Flip(directionInput);",
        "stateMachine.Airing(",
        'PlaySound("Attack",',
        "stateMachine.InputDir == Vector2.left || stateMachine.InputDir == Vector2.right",
        "stateMachine.inputController.GetMouseDirection() != stateMachine.InputDir.x",
        "stateMachine.Flip(0f - faceDir);",
        "if ((float)stateMachine.GetFaceDirection() == faceDir)",
        "stateMachine.Flip(faceDir);",
        "yield return MyWaitForUpdate.Get();\n\t\tstateMachine.ChangeState(PlayerStateType.Falling);",
    ):
        assert expression in pattern, expression
    distance = float(
        re.search(r"Move\(\(0f - faceDir\) \* ([\d.]+)f \* Vector3.right\)", pattern)[1]
    )
    flags = re.search(r"PlayerStateType.JumpAttack,\s*([^}]+)", code["DHUtil.PlayerFlags"])[1]
    assert flags.strip() == "PlayerStateFlags.Jump | PlayerStateFlags.JumpAttack"
    flag_values = {
        name: int(re.search(rf"\b{name} = (0x[0-9A-Fa-f]+|\d+)", code["PlayerStateFlags"])[1], 0)
        for name in ("Jump", "JumpAttack", "Attack")
    }
    assert (flag_values["Jump"] | flag_values["JumpAttack"]) & flag_values["Attack"] == 0
    player = code["PlayerStateMachine"]
    assert "[RequireComponent(typeof(PlayerInputController))]" in player
    assert (
        "base.CurrentStateType != PlayerStateType.JumpAttack && !CheckStateFlag(PlayerStateFlags.Attack)"
        in player
    )
    assert (
        "if (CheckStateFlag(PlayerStateFlags.Attack))\n\t\t\t{\n\t\t\t\tvelocity.x = 0f;" in player
    )
    assert (
        "Mathf.Sign(inputController.WorldScreenMousePosition().x - Collision2D.GetCenter().x)"
        in player
    )
    assert (
        "Mathf.Sign(WorldScreenMousePosition().x - base.transform.position.x)"
        in code["PlayerInputController"]
    )
    reset_climb = (
        code["PlayerCollision2D"]
        .split("public void ResetClimb()", 1)[1]
        .split("public void ResetClimbCeil()", 1)[0]
    )
    assert "collisionInfo.fallingThroughPlatform = false;" in reset_climb
    assert "collisionInfo.climbingWall = false;" in reset_climb
    assert "ResetClimbCeil();" in reset_climb
    dump(
        output / "air_attack.json",
        {
            "source": "INARI v0.2.1 / PlayerJumpAttackPattern",
            "exit_distance": distance,
            "entry_sound": "attack",
            "state_flags": ["Jump", "JumpAttack"],
            "flag_values": flag_values,
            "airborne_exit_wait_updates": 1,
            "source_sha256": {
                "Managed/Assembly-CSharp.dll": hashlib.sha256(assembly.read_bytes()).hexdigest()
            },
            "decompiled_sha256": {
                name: hashlib.sha256(value.encode("utf8")).hexdigest()
                for name, value in code.items()
            },
        },
    )
    print("Recovered JumpAttack exit offset:", distance, "Unity units")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--ilspy", type=Path, required=True)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.ilspy)
