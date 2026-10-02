"""Export the installed levels' wind triggers and retain native buff scheduling evidence."""

import argparse
import hashlib
import re
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, dump, PIXELS_PER_UNIT
from unity_scene_spatial import WorldTransforms


def export(source, decompiled, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    levels = {}
    for name in ("level15", "level25"):
        env = UnityPy.load(str(source / name))
        env.typetree_generator = generator
        transforms = {
            obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"
        }
        gos = {
            obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "GameObject"
        }
        by_go = {pose["m_GameObject"]["m_PathID"]: tid for tid, pose in transforms.items()}
        world = WorldTransforms(transforms)

        def active(tid):
            if not tid:
                return True
            pose = transforms[tid]
            return gos[pose["m_GameObject"]["m_PathID"]]["m_IsActive"] and active(
                pose["m_Father"]["m_PathID"]
            )

        levels[name] = []
        for obj in env.objects:
            if obj.type.name != "MonoBehaviour":
                continue
            if (
                obj.parse_monobehaviour_head().m_Script.read().m_ClassName
                != "MoveSpeedChangeTrigger"
            ):
                continue
            data = obj.read_typetree()
            go = data["m_GameObject"]["m_PathID"]
            if not data["m_Enabled"] or not active(by_go[go]):
                continue
            components = [
                PPtr(**entry["component"], assetsfile=obj.assets_file).deref()
                for entry in gos[go]["m_Component"]
            ]
            collider = next(c.read_typetree() for c in components if c.type.name == "BoxCollider2D")
            assert collider["m_Enabled"] and collider["m_IsTrigger"] and not data["once"]
            assert data["triggerLayer"]["m_Bits"] == 64
            spatial = world.sprite_plane(by_go[go], PIXELS_PER_UNIT)
            assert spatial["parallel"]
            levels[name].append(
                {
                    "go": go,
                    "id": data["id"],
                    "transform": spatial["transform"],
                    "size": [collider["m_Size"][axis] * PIXELS_PER_UNIT for axis in "xy"],
                    "offset": [
                        collider["m_Offset"]["x"] * PIXELS_PER_UNIT,
                        -collider["m_Offset"]["y"] * PIXELS_PER_UNIT,
                    ],
                    "cooldown": data["triggerCoolTime"],
                    "stamina": data["addStaminaAmount"],
                    "animator_id": data["animator"]["m_PathID"],
                }
            )
    code = (decompiled / "BuffComponent.cs").read_text(encoding="utf8")
    assert "float num = timer / duration;" in code
    assert (
        "timer += Time.deltaTime * Singleton<GameManager>.Instance.PlayerStateMachine.TimeScale;"
        in code
    )
    trigger = (decompiled / "MoveSpeedChangeTrigger.cs").read_text(encoding="utf8")
    assert "player.CurrentStateType == PlayerStateType.Spawn" in trigger
    assert "player.combatProfile.WindBuffDurations[num]" in trigger
    files = {name: source / name for name in ["level15", "level25", "Managed/Assembly-CSharp.dll"]}
    files.update(
        {
            name: decompiled / name
            for name in [
                "BuffComponent.cs",
                "BuffInfo.cs",
                "MoveSpeedChangeTrigger.cs",
                "Trigger.cs",
                "CustomCoroutine.cs",
                "CustomCoroutineManager.cs",
                "MyWaitForUpdate.cs",
                "PlayerStateMachine.cs",
                "Enemy.StateMachine/EnemyStateMachine.cs",
            ]
        }
    )
    dump(
        output,
        {
            "levels": levels,
            "story_heal": int(re.search(r"AddPlayerHp\((\d+)\)", trigger).group(1)),
            "source_sha256": {
                name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()
            },
        },
    )
    print("Native wind triggers:", {name: len(items) for name, items in levels.items()})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/wind_buff.json",
    )
