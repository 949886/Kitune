"""Recover the shipped ray spacing, ground snap and jump-corner correction."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

from import_inari import PIXELS_PER_UNIT, TypeTreeGenerator, UnityPy, dump
from unity_scene_spatial import WorldTransforms


def export(source, output, ilspy):
    assembly = source / "Managed/Assembly-CSharp.dll"
    code = {}
    for name in (
        "RaycastController",
        "RaycastCollision2D",
        "PlayerStateMachine",
        "DHUtil.PlayerFlags",
        "DHUtil.LayerMask.GetCollisionLayerMask",
    ):
        code[name] = subprocess.check_output(
            [str(ilspy), "-t", name, str(assembly)], encoding="utf8"
        )
    controller = code["RaycastController"]
    collision = code["RaycastCollision2D"]
    skin = float(re.search(r"skinWidth = ([\d.]+)f", controller)[1])
    intervals = float(
        re.search(r"maxStepHeight => base.HorizontalRaySpacing \* ([\d.]+)f", collision)[1]
    )
    assert "HorizontalRayCount = Mathf.RoundToInt(y / dstBetweenRays)" in controller
    assert "HorizontalRaySpacing = y / (float)(HorizontalRayCount - 1)" in controller
    assert "RayOrigins.bottomLeft, Vector2.down" in collision
    assert "RayOrigins.bottomRight, Vector2.down" in collision
    assert "((vector.y > vector2.y) ? vector : vector2)" in collision
    movement = (
        code["PlayerStateMachine"]
        .split("private void CalculateDashPosition()", 1)[1]
        .split("public void SetCurveMovement", 1)[0]
    )
    assert "if (!CheckStateFlag(PlayerStateFlags.DashAttack))" in movement
    assert "Collision2D.StickToGround(Collision2D.maxStepHeight)" in movement
    assert "dashStartPos += vector2" in movement and "DashTargetPos += vector2" in movement
    masks = code["DHUtil.LayerMask.GetCollisionLayerMask"]
    expression = re.search(r"Static = ([^;]+);", masks)[1]
    layers = re.findall(r"GetLayerMasks\.(\w+)", expression)
    assert layers == ["Ground", "Wall", "HardWall", "Platform"]
    direction_types = re.findall(
        r"PlayerCollisionType\.(\w+),\s*PlayerPhysicsFlags.DirectionMove",
        code["DHUtil.PlayerFlags"],
    )
    assert set(direction_types) == {"Dash", "DashAttack"}

    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    environment = UnityPy.load(str(source / "level1"))
    environment.typetree_generator = generator
    objects = list(environment.objects)
    component = next(
        obj
        for obj in objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "PlayerCollision2D"
    )
    data = component.read_typetree()
    collider = next(
        obj
        for obj in objects
        if obj.type.name == "BoxCollider2D"
        and obj.read_typetree()["m_GameObject"] == data["m_GameObject"]
    )
    size = collider.read_typetree()["m_Size"]
    transforms = {
        obj.path_id: obj.read_typetree()
        for obj in objects
        if obj.type.name in ("Transform", "RectTransform")
    }
    tid = next(
        key
        for key, transform in transforms.items()
        if transform["m_GameObject"] == data["m_GameObject"]
    )
    world = WorldTransforms(transforms).matrix(tid)
    # CalculateRaySpacing reads collider.bounds, rather than unscaled m_Size.
    # The native player has an identity world basis; reject changed source rigs.
    assert all(
        abs(world[row][column] - float(row == column)) < 1e-6
        for row in range(3)
        for column in range(3)
    )
    ray_count = round(size["y"] / data["dstBetweenRays"])
    assert ray_count >= 2
    spacing = size["y"] / (ray_count - 1)
    vertical_count = round(size["x"] / data["dstBetweenRays"])
    assert vertical_count >= 2
    assert "base.VerticalRaySpacing * base.VerticalRayCount" in collision
    assert "collisionInfo.rightUp && collisionInfo.leftUp" in collision
    assert "collisionInfo.moveAmount = Vector2.zero" in collision
    above = (
        code["PlayerStateMachine"]
        .split("private void OnAbove(", 1)[1]
        .split("private void OnStuck", 1)[0]
    )
    assert "Collision2D.AdjustCornerOffsetOnJump()" in above
    assert "velocity.y * Time.deltaTime * base.TimeScale - collisionInfo.moveAmount.y" in above
    assert (
        "PlayerStateFlags.AllIgnore" in above and "Collision2D.CollisionInfo.climbingWall" in above
    )
    ignored = re.findall(
        r"PlayerStateType\.(\w+),\s*PlayerStateFlags.AllIgnore", code["DHUtil.PlayerFlags"]
    )
    state_names = {"MultiThrow": "throw"}
    vertical = collision.split("protected virtual void VerticalCollisions(", 1)[1].split(
        "public void MoveByPlatform", 1
    )[0]
    ray_padding = float(re.search(r"Mathf.Abs\(moveAmount.y\) \+ ([\d.]+)f", vertical)[1])
    teleport = collision.split(
        "public virtual TeleportResult Teleport(Vector3 targetPosition, int collisionMask)", 1
    )[1].split("protected virtual void CheckFlip", 1)[0]
    attempts = int(re.search(r"i < (\d+)", teleport)[1])
    step_multiplier = float(re.search(r"0.015f \* ([\d.]+)f", teleport)[1])
    direction_block = re.search(
        r"iterationDirection = new Vector3\[8\]\s*\{(.*?)\};", collision, re.S
    )[1]
    axes = {"up": [0, -1], "down": [0, 1], "left": [-1, 0], "right": [1, 0]}
    search_directions = []
    for expression in direction_block.split(","):
        terms = re.findall(r"Vector3\.(\w+)", expression)
        assert terms and all(term in axes for term in terms)
        assert re.sub(r"Vector3\.\w+|[+\s]", "", expression) == ""
        search_directions.append([sum(axes[term][axis] for term in terms) for axis in range(2)])
    assert len(search_directions) == 8
    ignored_platform = re.search(r"IgnorePlatform = ([^;]+);", masks)[1]
    jump_layers = re.findall(r"GetLayerMasks\.(\w+)", ignored_platform)
    assert jump_layers == ["Ground", "Wall", "HardWall", "InteractiveWall"]
    globals_env = UnityPy.load(str(source / "globalgamemanagers"))
    query_settings = next(
        obj.read_typetree() for obj in globals_env.objects if obj.type.name == "Physics2DSettings"
    )
    result = {
        "source": "INARI v0.2.1 / CalculateDashPosition + StickToGround + OnAbove",
        "component_id": component.path_id,
        "body_size": size,
        "pixels_per_unit": PIXELS_PER_UNIT,
        "distance_between_rays": data["dstBetweenRays"],
        "horizontal_ray_count": ray_count,
        "horizontal_ray_spacing": spacing,
        "step_ray_intervals": intervals,
        "maximum_step_height": spacing * intervals,
        "skin_width": skin,
        "jump_corner": {
            "vertical_ray_count": vertical_count,
            "vertical_ray_spacing": size["x"] / (vertical_count - 1),
            "ray_padding": ray_padding,
            "ignored_states": [state_names[name] for name in ignored],
            "teleport_attempts": attempts,
            "teleport_step_multiplier": step_multiplier,
            "search_directions": search_directions,
            "collision_layers": jump_layers,
        },
        "static_layers": layers,
        "excluded_state_flag": "DashAttack",
        "snap_collision_types": [name for name in direction_types if name != "DashAttack"],
        "queries_start_in_colliders": query_settings["m_QueriesStartInColliders"],
        "queries_hit_triggers": query_settings["m_QueriesHitTriggers"],
        "source_sha256": {
            name: hashlib.sha256((source / name).read_bytes()).hexdigest()
            for name in ("level1", "globalgamemanagers", "Managed/Assembly-CSharp.dll")
        },
        "decompiled_sha256": {
            name: hashlib.sha256(text.encode("utf8")).hexdigest() for name, text in code.items()
        },
    }
    dump(output / "ground_snap.json", result)
    print(
        "Recovered ray count:",
        ray_count,
        "maximum snap pixels:",
        spacing * intervals * PIXELS_PER_UNIT,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--ilspy", type=Path, required=True)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.ilspy)
