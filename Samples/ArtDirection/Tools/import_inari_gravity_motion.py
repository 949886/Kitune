"""Recover INARI's gravity-based attack/hit driver from the shipped assembly."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

from import_inari import UnityPy, dump


def export(source, output, ilspy):
    assembly = source / "Managed/Assembly-CSharp.dll"
    code = {
        name: subprocess.check_output([str(ilspy), "-t", name, str(assembly)], encoding="utf8")
        for name in (
            "PlayerStateMachine",
            "PlayerCollision2D",
            "PlayerAttackPattern",
            "PlayerStrongAttackPattern",
            "PlayerJumpAttackPattern",
            "RaycastCollision2D",
            "DHUtil.PlayerFlags",
            "DHUtil.LayerMask.GetCollisionLayerMask",
        )
    }
    player = code["PlayerStateMachine"]
    movement = player.split("private void CalculateDashPositionWithGravity()", 1)[1].split(
        "private void CalculateDashPosition()", 1
    )[0]
    multiplier = float(re.search(r"private float extraDashXMultiplier = ([\d.]+)f;", player)[1])
    threshold = float(re.search(r"Mathf.Abs\(InputDir.x\) > ([\d.]+)f", movement)[1])
    excluded = re.findall(r"Collision2D.CollisionType == PlayerCollisionType\.(\w+)", movement)
    for expression in (
        "velocity.y += gravity * Time.deltaTime * base.TimeScale",
        "(DashTargetPos - dashStartPos) / Collision2D.DashTime",
        "Mathf.Lerp(t: dashMoveCurve.Evaluate(Collision2D.DashRadio), a: vector.x, b: 0f)",
        "gravity * Collision2D.DashingTime",
        "Collision2D.DashRadio >= 1f",
        "PlayerStateType.StrongAttack && Collision2D.CheckWallandGround(vector3.normalized, vector3.magnitude)",
        "Collision2D.Move(vector3);\n\t\tvelocity = vector2;",
        "Collision2D.Move(vector);\n\t\tCollision2D.ResetDash();",
    ):
        assert expression in movement, expression
    collision = code["RaycastCollision2D"]
    guard = collision.split("public bool CheckWallandGround(", 1)[1].split(
        "public bool TryClimbStep", 1
    )[0]
    depth = float(re.search(r"hitBuffer, ([\d.]+)f, GetCollisionLayerMask.Default", guard)[1])
    assert guard.index("RayOrigins.bottomRight") < guard.index("GetWallPoint(dir, checkDistance)")
    wall = collision.split("public Vector3? GetWallPoint(", 1)[1].split(
        "public bool CheckAbove", 1
    )[0]
    assert "UpdateRaycastOrigins();" in wall and "GetCollisionLayerMask.Static" in wall
    assert "GetLayer.Door && !isCheckDoor" in wall
    land = (
        code["PlayerCollision2D"]
        .split("public void Land()", 1)[1]
        .split("public void Coyote()", 1)[0]
    )
    assert "if (!beforeCollisionInfo.below)" in land and "PlayerCollisionType.Idle" in land
    attack_patterns = ["PlayerAttackPattern", "PlayerStrongAttackPattern"]
    for name in attack_patterns:
        gate = code[name].split("void ApplyAttackMovement(", 1)[1].split("\n\t}", 1)[0]
        assert "if (!stateMachine.Collision2D.CheckAttackEnemyContact(stateMachine))" in gate
        assert "stateMachine.AttackMovement(" in gate
    assert "CheckAttackEnemyContact" not in code["PlayerJumpAttackPattern"]
    assert "stateMachine.Airing(" in code["PlayerJumpAttackPattern"]
    contact = code["PlayerCollision2D"].split("public bool CheckAttackEnemyContact(", 1)[1]
    contact_field = re.search(r"base.ColliderSize \+ player.combatProfile\.(\w+)", contact)[1]
    assert "OverlapBoxNonAlloc(GetCenter()," in contact
    assert "0f, colliderBuffer, GetLayerMasks.Enemy) > 0" in contact
    types = re.findall(
        r"PlayerCollisionType\.(\w+),\s*PlayerPhysicsFlags.GravityDirectionMove",
        code["DHUtil.PlayerFlags"],
    )
    assert set(types) == {"Attack", "Hit"}
    masks = code["DHUtil.LayerMask.GetCollisionLayerMask"]
    layers = {
        key.lower()
        + "_layers": re.findall(r"GetLayerMasks\.(\w+)", re.search(rf"{key} = ([^;]+);", masks)[1])
        for key in ("Static", "Default")
    }
    assert layers["default_layers"] == layers["static_layers"] + ["InteractiveWall"]
    environment = UnityPy.load(str(source / "globalgamemanagers"))
    queries = next(
        obj.read_typetree() for obj in environment.objects if obj.type.name == "Physics2DSettings"
    )
    dump(
        output / "gravity_motion.json",
        {
            "source": "INARI v0.2.1 / CalculateDashPositionWithGravity + ResetDashMovement",
            "collision_types": types,
            "extra_input_multiplier": multiplier,
            "active_input_threshold": threshold,
            "no_extra_input_types": excluded,
            "ground_check_distance": depth,
            "attack_contact": {
                "patterns": attack_patterns,
                "size_profile_field": contact_field,
                "layer": "Enemy",
                "angle": 0,
            },
            "queries_hit_triggers": queries["m_QueriesHitTriggers"],
            "queries_start_in_colliders": queries["m_QueriesStartInColliders"],
            **layers,
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                for name in ("globalgamemanagers", "Managed/Assembly-CSharp.dll")
            },
            "decompiled_sha256": {
                name: hashlib.sha256(value.encode("utf8")).hexdigest()
                for name, value in code.items()
            },
        },
    )
    print("Recovered gravity motion:", types, "input multiplier:", multiplier)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--ilspy", type=Path, required=True)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.ilspy)
