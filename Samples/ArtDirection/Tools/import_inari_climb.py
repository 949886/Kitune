"""Recover climb animation branches and the shipped wall-hold update contract."""

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
            "PlayerClimbState",
            "PlayerShurikenDashPatter",
            "PlayerStateMachine",
            "PlayerCollision2D",
            "RaycastCollision2D",
            "DHUtil.PlayerFlags",
            "DHUtil.LayerMask.GetCollisionLayerMask",
        )
    }
    climb = code["PlayerClimbState"]
    assert "!base.StateMachine.Collision2D.CollisionInfo.above" in climb
    assert "base.StateMachine.Velocity.y > 0f" in climb
    assert "base.StateMachine.Velocity.y < 0f" in climb
    assert "collisionInfo.right && !collisionInfo.bottomRight" in climb
    assert "collisionInfo.left && !collisionInfo.bottomLeft" in climb
    clips = {
        "ClimbUp": "climb_up",
        "ClimbDown": "climb_down",
        "ClimbCorner": "climb_corner",
        "Climb": "climb",
        "ClimbCeiling": "climb_ceiling",
    }
    assert set(re.findall(r"GetAnimationParameter\.(\w+)", climb)) == set(clips)
    machine = code["PlayerStateMachine"]
    update = machine.split("private void Update()", 1)[1].split("private void LateUpdate()", 1)[0]
    assert re.search(
        r"if \(!CheckStateFlag\(PlayerStateFlags.AllIgnore\)\)\s*\{\s*"
        r"PlayerStateType playerStateType = Collision2D.UpdateCollision\(this\)",
        update,
    )
    # LateUpdate does not call HandleClimb while hanging from a ceiling. Its
    # timeout branch is consequently unreachable during an ordinary ceiling hold.
    late = machine.split("private void LateUpdate()", 1)[1]
    assert re.search(
        r"else if \(!Collision2D.CollisionInfo.climbingCeil\)\s*\{\s*CalculatedMovement\(\)", late
    )
    collision = code["PlayerCollision2D"]
    assert "public float WallHoldingTime" in collision
    land = collision.split("public void Land()", 1)[1].split("public void Coyote()", 1)[0]
    assert "if (!beforeCollisionInfo.below)" in land
    assert "WallHoldingTime = physicsProfile.WallHoldingTime" in land
    reset = collision.split("public void Reset()", 1)[1].split("public bool CheckEnemyContact", 1)[
        0
    ]
    assert "WallHoldingTime = physicsProfile.WallHoldingTime" in reset
    assert re.search(r"public void PhysicsReset\(\)\s*\{\s*Collision2D.Reset\(\)", machine)
    assert re.search(
        r"if \(WallHoldingTime > 0f\)\s*\{\s*"
        r"WallHoldingTime -= Time.deltaTime \* playerStateMachine.TimeScale;",
        collision,
    )
    ignored = re.findall(
        r"PlayerStateType\.(\w+),\s*PlayerStateFlags.AllIgnore", code["DHUtil.PlayerFlags"]
    )
    states = {"MultiThrow": "throw"}
    horizontal = (
        code["RaycastCollision2D"]
        .split("protected virtual void HorizontalCollisions(", 1)[1]
        .split("protected virtual void VerticalCollisions(", 1)[0]
    )
    distance = float(re.search(r"distance = ([\d.]+)f;", horizontal)[1])
    assert "Mathf.Abs(moveAmount.x) < 0.015f" in horizontal
    assert "raycastHit2D.distance != 0f" in horizontal
    assert "distance = raycastHit2D.distance + 0.015f" in horizontal
    teleport = collision.split(
        "public void Teleport(Vector3 targetPosition, int collisionMask, bool isStuck)", 1
    )[1].split("public void ResetGroundPosition", 1)[0]
    angles = re.search(
        r"num2 == 1f\) \? new Vector3\(0f, 0f, ([\d.]+)f\) : new Vector3\(0f, 0f, ([\d.]+)f\)",
        teleport,
    )
    assert angles
    probe_scale = float(re.search(r"bounds.extents.x \* ([\d.]+)f", teleport)[1])
    assert (
        teleport.index("RayOrigins.centerLeft")
        < teleport.index("RayOrigins.bottomLeft", teleport.index("RayOrigins.centerLeft"))
        < teleport.index("RayOrigins.topLeft", teleport.index("RayOrigins.centerLeft"))
    )
    reset_ceiling = collision.split("public void ResetClimbCeil()", 1)[1].split(
        "public void ResetDash()", 1
    )[0]
    release_scale = float(
        re.search(r"base.ColliderSize.y \* Vector3.down \* ([\d.]+)f", reset_ceiling)[1]
    )
    layer_expression = re.search(
        r"StuckLayer = ([^;]+);", code["DHUtil.LayerMask.GetCollisionLayerMask"]
    )[1]
    stuck_layers = re.findall(r"GetLayerMasks\.(\w+)", layer_expression)
    assert stuck_layers == ["Ground", "Wall"]
    assert "stateMachine.PhysicsReset();" in code["PlayerShurikenDashPatter"]
    assert "stateMachine.ShurikenTeleport();" in code["PlayerShurikenDashPatter"]
    entity_distance = float(
        re.search(r"GetWallPoint\(teleportResult.WallDirection, ([\d.]+)f\)", teleport)[1]
    )
    entity_skin = float(
        re.search(r"WallDirection.normalized \* base.SkinWidth \* ([\d.]+)f", teleport)[1]
    )
    assert "teleportResult.WallDirection != Vector3.down" in teleport
    assert "StickToGround(base.maxStepHeight)" in teleport
    assert "base.HorizontalRaySpacing) * (float)i" in teleport
    assert "base.Collider2D.bounds.extents.y, collisionMask" in teleport
    teleport_settings = {
        "entity_wall_distance": entity_distance,
        "entity_skin_multiplier": entity_skin,
        "wall_excluded_layer": "HardWall",
    }
    ceiling = {
        "rightward_degrees": (-float(angles[1]) + 180) % 360 - 180,
        "leftward_degrees": (-float(angles[2]) + 180) % 360 - 180,
        "probe_extent_scale": probe_scale,
        "origins": ["center", "bottom", "top"],
        "release_height_scale": release_scale,
        "stuck_layers": stuck_layers,
    }
    dump(
        output / "climb.json",
        {
            "source": "INARI v0.2.1 / PlayerClimbState + UpdateCollision + LateUpdate",
            "stationary_ray_distance": distance,
            "timer_ignored_states": [states[name] for name in ignored],
            "ceiling_skips_normal_movement": True,
            "ceiling": ceiling,
            "teleport": teleport_settings,
            "clips": clips,
            "assembly_sha256": hashlib.sha256(assembly.read_bytes()).hexdigest(),
            "decompiled_sha256": {
                name: hashlib.sha256(text.encode("utf8")).hexdigest() for name, text in code.items()
            },
        },
    )
    print("Recovered original climb branches and stationary ray distance:", distance)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--ilspy", type=Path, required=True)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.ilspy)
