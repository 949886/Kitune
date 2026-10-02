"""Export original bow attack anchors and serialized decision settings."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr
from import_inari_damage import number
from unity_scene_spatial import WorldTransforms


def export(source, decompiled, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "level15"))
    env.typetree_generator = generator
    transforms = {o.path_id: o.read_typetree() for o in env.objects if o.type.name == "Transform"}
    by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}
    world = WorldTransforms(transforms)
    imported = json.loads((output / "level15.json").read_text(encoding="utf8"))
    actors = {actor["go"]: actor for actor in imported["enemies"] if actor["kind"] == "EnemyBowMan"}
    melee_code = (decompiled / "Enemy.State/EnemyMeleePattern.cs").read_text(encoding="utf8")
    result = {"actors": {}, "wall_damage": number(melee_code, r"RequestDamage\(([\d.]+)f")}
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if (
            head.m_GameObject.path_id not in actors
            or head.m_Script.read().m_ClassName != "EnemyBowMan"
        ):
            continue
        actor = actors[head.m_GameObject.path_id]
        value = obj.read_typetree()
        target = by_go[value["attackPoint"]["m_PathID"]]
        anchor = target
        while transforms[anchor]["m_GameObject"]["m_PathID"] not in actor["visuals"]:
            anchor = transforms[anchor]["m_Father"]["m_PathID"]
            assert anchor, "Arrow origin must resolve to a tracked visual ancestor"
        target_pose = world.sprite_plane(target, 16.0)
        anchor_pose = world.sprite_plane(anchor, 16.0)
        assert target_pose["parallel"] and anchor_pose["parallel"]
        a, b, c, d, x, y = anchor_pose["transform"]
        delta_x = target_pose["transform"][4] - x
        delta_y = target_pose["transform"][5] - y
        determinant = a * d - b * c
        result["actors"][str(actor["go"])] = {
            "attack_point_go": value["attackPoint"]["m_PathID"],
            "anchor_go": transforms[anchor]["m_GameObject"]["m_PathID"],
            "anchor_local": [
                (d * delta_x - c * delta_y) / determinant,
                (-b * delta_x + a * delta_y) / determinant,
            ],
            "source_position": target_pose["transform"][4:6],
            "can_alarm": value["IsCanAlarm"],
            "run_away_weight": value["RunAwayWeight"],
            "confirm_effect_frame": value["AttackConfirmEffectFrame"],
        }
    assert len(result["actors"]) == len(actors)
    code_files = [
        "Enemy/EnemyBowMan.cs",
        "Enemy.State/EnemyAttackReadyPattern.cs",
        "Enemy.State/EnemyAttackConfirmPattern.cs",
        "Enemy.State/EnemyRangePattern.cs",
        "Enemy.State/EnemyMeleePattern.cs",
        "Enemy.State/EnemyAttackPattern.cs",
        "Enemy.State/EnemyAttackPostPattern.cs",
        "Enemy.State/AttackState.cs",
        "Enemy.State/EnemyAttackCancelPattern.cs",
        "StateMachine.cs",
        "Enemy.StateMachine/EnemyStateMachine.cs",
        "EnemyShurikenComponent.cs",
        "WeakPointComponent.cs",
        "EnemyPattern.cs",
        "RotationPart.cs",
    ]
    result["source_sha256"] = {
        name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest() for name in code_files
    }
    for name in ["level15", "Managed/Assembly-CSharp.dll"]:
        result["source_sha256"][name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
    shared_names = [
        "Enemy.State/EnemyChasePattern.cs",
        "Enemy.State/EnemyRunAwayPattern.cs",
        "Enemy.State/EnemyLeashBackPattern.cs",
        "Enemy.State/EnemyIdlePattern.cs",
        "Enemy.State/EnemyRetargetPattern.cs",
        "EnemyCheckDoorPattern.cs",
        "RangedPositioningRule.cs",
    ]
    shared = {name: (decompiled / name).read_text(encoding="utf8") for name in shared_names}
    result["source_sha256"].update(
        {name: hashlib.sha256(text.encode("utf8")).hexdigest() for name, text in shared.items()}
    )
    retreat = shared["Enemy.State/EnemyRunAwayPattern.cs"]
    positioning = shared["RangedPositioningRule.cs"]
    assert "IsSkippAttack" not in (decompiled / "Enemy/EnemyBowMan.cs").read_text(encoding="utf8")
    result["common"] = {
        "arrival_distance": number(
            (decompiled / "StateMachine.cs").read_text(encoding="utf8"),
            r"GetGrondTilePoint\(\)\.x - pos\.x\) < ([\d.]+)f",
        ),
        "chase_path_fraction": number(
            shared["Enemy.State/EnemyChasePattern.cs"], r"AttackRange\.x \* ([\d.]+)f"
        ),
        "retreat": {
            "minimum_distance": number(retreat, r"endPos.x - vector.x\) < ([\d.]+)f"),
            "separation_radius": number(
                retreat, r"FindNearestNonOverlapPosition\(endPos, ([\d.]+)f"
            ),
            "search_cells": int(
                number(retreat, r"FindNearestNonOverlapPosition\(endPos, [\d.]+f, (\d+)")
            ),
        },
        "positioning": {
            "path_nodes": number(positioning, r"NearestEnemies\(rangedEnemy, ([\d.]+)f"),
            "count_threshold": int(number(positioning, r"_nearestEnemiesCache.Count > (\d+)")),
        },
        "door": {
            "damage": number(shared["EnemyCheckDoorPattern.cs"], r"Amount = ([\d.]+)f"),
            "chase_skip_ready": False,
            "chase_skip_confirm": False,
            "retreat_skip_ready": False,
            "retreat_skip_confirm": False,
        },
    }
    (output / "bow_combat.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print("Imported bow attack anchors", result["actors"])


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
