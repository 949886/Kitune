"""Recover PlayerCollision2D's post-movement enemy separation contract."""

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
        for name in ("PlayerCollision2D", "GameManager")
    }
    collision = code["PlayerCollision2D"]
    move = collision.split("public override Vector2 Move(Vector2 moveAmount)", 1)[1].split(
        "private void SnapToPixel", 1
    )[0]
    width = float(re.search(r"CheckEnemyContact\(float scale = ([\d.]+)f\)", collision)[1])
    minimum = float(re.search(r"1f / Mathf.Max\(a, ([\d.]+)f\)", move)[1])
    clamp = re.search(r"Mathf.Clamp\(value, ([\d.]+)f, ([\d.]+)f\)", move)
    field = re.search(r"num \* physicsProfile\.(\w+) \* value", move)[1]
    for expression in (
        "Vector2 vector = base.Move(moveAmount);",
        "Collider2D collider2D = colliderBuffer[0];",
        "GetEnemy(collider2D.transform)",
        "enemy.CurrentStateType != EnemyStateType.RunAway",
        "GetCenter().x - enemy.Collision2D.GetCenter().x",
        "vector.x += num * physicsProfile.EnemyDrag * value;",
        "base.Move(new Vector2(num * physicsProfile.EnemyDrag * value, 0f) * Time.deltaTime * TimeScale);",
        "collisionInfo.faceDir = faceDir;",
        "return vector * num3;",
    ):
        assert expression in move, expression
    assert (
        "base.ColliderSize + Vector2.right * scale, 0f, colliderBuffer, GetLayerMasks.Enemy"
        in collision
    )
    assert "enemyStateMachines[transform].gameObject.activeInHierarchy" in code["GameManager"]
    environment = UnityPy.load(str(source / "globalgamemanagers"))
    queries = next(
        obj.read_typetree() for obj in environment.objects if obj.type.name == "Physics2DSettings"
    )
    dump(
        output / "enemy_contact.json",
        {
            "source": "INARI v0.2.1 / PlayerCollision2D.Move + CheckEnemyContact",
            "extra_width": width,
            "minimum_distance": minimum,
            "weight_minimum": float(clamp[1]),
            "weight_maximum": float(clamp[2]),
            "physics_profile_field": field,
            "excluded_state": "RunAway",
            "layer": "Enemy",
            "queries_hit_triggers": queries["m_QueriesHitTriggers"],
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
    print("Recovered enemy separation: width", width, "weight clamp", clamp[1], clamp[2])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--ilspy", type=Path, required=True)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI", args.ilspy)
