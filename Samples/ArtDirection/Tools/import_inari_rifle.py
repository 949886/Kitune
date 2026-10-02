"""Extract this build's rifle timing, line renderers and original line texture."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, rgba
from import_inari_damage import number
from unity_scene_spatial import WorldTransforms


def export(source, decompiled, output):
    names = (
        "Enemy/EnemyRifleMan.cs",
        "Enemy.State/EnemyRayAttackPattern.cs",
        "Enemy.State/EnemyAttackReadyPattern.cs",
        "Enemy.State/EnemyAttackConfirmPattern.cs",
        "Enemy.State/EnemyAttackPostPattern.cs",
        "DHUtil.RunTime/CoroutinUtil.cs",
        "Enemy.State/EnemyIdlePattern.cs",
        "Enemy.State/EnemyLeashBackPattern.cs",
        "Enemy.StateMachine/EnemyStateMachine.cs",
        "StateMachine.cs",
        "Enemy.State/EnemyChasePattern.cs",
        "Enemy.State/EnemyRunAwayPattern.cs",
        "RaycastCollision2D.cs",
        "PathFindingManager.cs",
        "GameManager.cs",
        "EnemyCheckDoorPattern.cs",
        "InteractiveDoor.cs",
        "RangedPositioningRule.cs",
        "Enemy.State/EnemyRetargetPattern.cs",
        "Enemy.State/AttackReadyState.cs",
        "Enemy.State/AttackState.cs",
    )
    texts = {name: (decompiled / name).read_text(encoding="utf8") for name in names}
    rifle, ray = texts[names[0]], texts[names[1]]
    result = {
        "positioning": {
            "path_nodes": number(
                texts["RangedPositioningRule.cs"], r"NearestEnemies\(rangedEnemy, ([\d.]+)f"
            ),
            "count_threshold": int(
                number(texts["RangedPositioningRule.cs"], r"_nearestEnemiesCache.Count > (\d+)")
            ),
        },
        "door": {
            "damage": number(texts["EnemyCheckDoorPattern.cs"], r"Amount = ([\d.]+)f"),
            "chase_skip_ready": bool(
                re.search(r"(?m)^\s*checkDoorPattern.IsSkippAttackReady = true;", rifle)
            ),
            "chase_skip_confirm": bool(
                re.search(r"(?m)^\s*checkDoorPattern.IsSkippAttackConfirm = true;", rifle)
            ),
            "retreat_skip_ready": "enemyRunAwayPattern.checkDoorPattern.IsSkippAttackReady = true"
            in rifle,
            "retreat_skip_confirm": "enemyRunAwayPattern.checkDoorPattern.IsSkippAttackConfirm = true"
            in rifle,
        },
        "retreat": {
            "minimum_distance": number(
                texts["Enemy.State/EnemyRunAwayPattern.cs"], r"endPos.x - vector.x\) < ([\d.]+)f"
            ),
            "separation_radius": number(
                texts["Enemy.State/EnemyRunAwayPattern.cs"],
                r"FindNearestNonOverlapPosition\(endPos, ([\d.]+)f",
            ),
            "search_cells": int(
                number(
                    texts["Enemy.State/EnemyRunAwayPattern.cs"],
                    r"FindNearestNonOverlapPosition\(endPos, [\d.]+f, (\d+)",
                )
            ),
        },
        "chase_path_fraction": number(
            texts["Enemy.State/EnemyChasePattern.cs"], r"AttackRange\.x \* ([\d.]+)f"
        ),
        "arrival_distance": number(
            texts["StateMachine.cs"], r"GetGrondTilePoint\(\)\.x - pos\.x\) < ([\d.]+)f"
        ),
        "tracking_fraction": number(rifle, r"MovementSpeed\) \* ([\d.]+)f"),
        "damage": number(ray, r"entity.RequestDamage\(([\d.]+)f"),
        "shot_distance": number(ray, r"vector, buffer, ([\d.]+)f"),
        "aim_distance": number(rifle, r"CollisionInfo.faceDir, ([\d.]+)f"),
        "tracer_time": number(rifle, r"float animationTime = ([\d.]+)f"),
        "source_sha256": hashlib.sha256(
            (source / "Managed/Assembly-CSharp.dll").read_bytes()
        ).hexdigest(),
        "scene_sha256": hashlib.sha256((source / "level15").read_bytes()).hexdigest(),
        "decompiled_sha256": {
            name: hashlib.sha256(text.encode("utf8")).hexdigest() for name, text in texts.items()
        },
        "actors": {},
        "material_file_sha256": {},
    }
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "level15"))
    env.typetree_generator = generator
    scene_path = output / "level15.json"
    scene = json.loads(scene_path.read_text(encoding="utf8"))
    doors = {door["go"]: door for door in scene["doors"]}
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if (
            head.m_GameObject.path_id in doors
            and head.m_Script.read().m_ClassName == "InteractiveDoor"
        ):
            data = obj.read_typetree()
            doors[head.m_GameObject.path_id].update(
                health=data["MaxHealth"], invincible=bool(data["IsInvincible"])
            )
    scene_path.write_text(json.dumps(scene, separators=(",", ":")) + "\n", encoding="utf8")
    transforms = {
        obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"
    }
    by_go = {data["m_GameObject"]["m_PathID"]: tid for tid, data in transforms.items()}
    world = WorldTransforms(transforms)
    selected = {
        enemy["go"]
        for enemy in json.loads((output / "level15.json").read_text(encoding="utf8"))["enemies"]
    }
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        go = head.m_GameObject.path_id
        if go not in selected or head.m_Script.read().m_ClassName != "EnemyRifleMan":
            continue
        data = obj.read_typetree()
        actor = {}
        rotating_gos = {
            PPtr(**reference, assetsfile=obj.assets_file).read_typetree()["m_GameObject"][
                "m_PathID"
            ]
            for reference in data["rotationPart"]["RotationSpriteInfos"]["keys"]
        }
        for label, field in (("aim", "LineRenderer"), ("tracer", "AttackRangeLineRenderer")):
            renderer_obj = PPtr(**data[field], assetsfile=obj.assets_file).deref()
            renderer = renderer_obj.read_typetree()
            line_go = renderer["m_GameObject"]["m_PathID"]
            ancestor = by_go[line_go]
            while ancestor and transforms[ancestor]["m_GameObject"]["m_PathID"] not in rotating_gos:
                ancestor = transforms[ancestor]["m_Father"]["m_PathID"]
            assert ancestor, "Line renderer must be attached to an imported rotating gun part"
            mat = PPtr(**renderer["m_Materials"][0], assetsfile=renderer_obj.assets_file).deref()
            material = mat.read_typetree()
            result["material_file_sha256"][mat.assets_file.name] = hashlib.sha256(
                (source / mat.assets_file.name).read_bytes()
            ).hexdigest()
            props = material["m_SavedProperties"]
            colors, floats = dict(props["m_Colors"]), dict(props["m_Floats"])
            main = dict(props["m_TexEnvs"])["_MainTex"]["m_Texture"]
            texture = None
            if main["m_PathID"]:
                source_texture = PPtr(**main, assetsfile=mat.assets_file).read()
                pixels = source_texture.image.convert("RGBA")
                path = "Textures/rifle_tracer.png"
                pixels.save(output / path)
                import_path = (output / path).with_suffix(".png.import")
                if import_path.exists():
                    options = import_path.read_text(encoding="utf8")
                    import_path.write_text(
                        options.replace(
                            "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                        ),
                        encoding="utf8",
                    )
                texture = {
                    "path": path,
                    "pixel_sha256": hashlib.sha256(pixels.tobytes()).hexdigest(),
                }
            actor[label] = {
                "transform": world.sprite_plane(by_go[line_go], 16.0)["transform"],
                "anchor_go": transforms[ancestor]["m_GameObject"]["m_PathID"],
                "parameters": renderer["m_Parameters"],
                "sort": [renderer["m_SortingLayer"], renderer["m_SortingOrder"]],
                "texture": texture,
                "material": {
                    "name": material["m_Name"],
                    "keywords": material["m_ValidKeywords"],
                    "color": rgba(colors["_Color"]),
                    "glow_color": rgba(colors["_GlowColor"]),
                    "floats": {
                        name: floats[name]
                        for name in ("_Alpha", "_FadeAmount", "_Glow", "_GlowGlobal")
                        if name in floats
                    },
                },
            }
        result["actors"][str(go)] = actor
    (output / "rifle_combat.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(f"Exported source rifle rules and {len(result['actors'])} pairs of line renderers")


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
