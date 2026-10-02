"""Export active source enemies and their damage/death presentation dependencies."""

import hashlib
import UnityPy
from unity_scene_animation import animator_tracks, target_paths
from unity_scene_spatial import WorldTransforms
from unity_enemy_combat import combat_animations, ranged_presentation


def runtime_navigation_grid(importer):
    path = importer.source / "level1"
    env = UnityPy.load(str(path))
    env.typetree_generator = importer.generator
    transforms = {
        obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"
    }
    by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}
    world = WorldTransforms(transforms)
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "GameManager":
            continue
        # This stripped manager has additional trailing serialized data. Only
        # consume its known prefix, then independently validate the Grid reference.
        data = obj.read_typetree(check_read=False)
        pointer = importer.pointer(obj.assets_file, data["PathFindingManager"]["tileMapGrid"])
        assert pointer.deref().type.name == "Grid"
        grid = pointer.read_typetree()
        assert grid["m_CellLayout"] == 0 and grid["m_CellSwizzle"] == 0
        return dict(
            grid=world.sprite_plane(by_go[grid["m_GameObject"]["m_PathID"]], 16.0),
            cell_size=[grid["m_CellSize"]["x"], grid["m_CellSize"]["y"]],
            grid_source=dict(
                file="level1",
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                id=pointer.path_id,
            ),
        )
    raise ValueError("Missing runtime navigation Grid")


def collect_navigation(importer, objects):
    """Keep the shipped walkable cell map; do not infer paths from painted tiles."""
    result = {}
    for obj in objects:
        if obj.type.name != "MonoBehaviour":
            continue
        kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
        if kind == "SceneRoot":
            source = obj.read_typetree()
            reference = importer.pointer(obj.assets_file, source["SceneReferenceData"])
            data = reference.read_typetree()
            path = importer.pointer(reference.deref().assets_file, data["TileMapPathData"])
            if not path:
                continue
            cells = path.read_typetree()["GroundTileMapArea"]
            result["ground"] = [
                [cell["x"], cell["y"]]
                for cell, kind in zip(cells["keys"], cells["values"])
                if kind == 0  # TileMapType.Ground
            ]
            result["walls"] = [
                [cell["x"], cell["y"]]
                for cell, kind in zip(cells["keys"], cells["values"])
                if kind == 1  # TileMapType.Wall blocks the horizontal separation search.
            ]
            result["source_file"] = path.deref().assets_file.name
            result["non_wall"] = [
                [cell["x"], cell["y"]]
                for cell, kind in zip(cells["keys"], cells["values"])
                if kind != 1
            ]
            importer.navigation_source_files.add(result["source_file"])
            result["source_id"] = path.path_id
    if result:
        result.update(importer.navigation_grid)
    return result


def movement_tracks(importer, animator, controller, paths, transforms, by_go):
    """Resolve animation triggers, since bow patrol uses a second Run state."""
    names = dict(controller["m_TOS"])
    machine = controller["m_Controller"]["m_StateMachineArray"][0]["data"]
    result = {}
    for transition in machine["m_AnyStateTransitionConstantArray"]:
        transition = transition["data"]
        conditions = transition["m_ConditionConstantArray"]
        if len(conditions) != 1:
            continue
        condition = conditions[0]["data"]
        trigger = names.get(condition["m_EventID"])
        if trigger not in ("Idle", "MoveX") or condition["m_ConditionMode"] != 1:
            continue
        result[trigger] = animator_tracks(
            importer, animator, paths, transforms, by_go, transition["m_DestinationState"]
        )
    return result


def collect_enemies(importer, objects, gos, transforms, by_go, active, spatial, visual_gos, order):
    enemies = []
    for obj in objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        kind = head.m_Script.read().m_ClassName
        go = head.m_GameObject.path_id
        if not kind.startswith("Enemy") or not active(by_go[go]):
            continue
        data = obj.read_typetree()
        if "enemyProfile" not in data or not data["m_Enabled"]:
            continue

        def read(pointer):
            return importer.pointer(obj.assets_file, pointer).read_typetree()

        profile = read(data["enemyProfile"])
        entity = read(data["Entity"])
        collision = read(data["Collision2D"])
        body = read(collision["collider2D"])
        root_pose = spatial.sprite_plane(by_go[go], 16.0)
        body_pose = spatial.sprite_plane(by_go[body["m_GameObject"]["m_PathID"]], 16.0)
        assert body_pose["parallel"] and abs(body_pose["transform"][1]) < 1e-5
        assert abs(body_pose["transform"][2]) < 1e-5
        matrix = body_pose["transform"]
        bounds_offset = [
            matrix[4] - root_pose["transform"][4] + body["m_Offset"]["x"] * 16.0 * matrix[0],
            matrix[5] - root_pose["transform"][5] - body["m_Offset"]["y"] * 16.0 * matrix[3],
        ]
        paths = target_paths(go, gos, transforms, by_go)
        visual_ids = sorted(set(paths.values()) & visual_gos)
        if not visual_ids:
            continue

        animator = importer.pointer(obj.assets_file, data["Animator"]).deref()
        controller = animator.read().m_Controller.read_typetree()
        state_names = dict(controller["m_TOS"])
        states = controller["m_Controller"]["m_StateMachineArray"][0]["data"][
            "m_StateConstantArray"
        ]
        animation_go = animator.read().m_GameObject.path_id
        animation_paths = target_paths(animation_go, gos, transforms, by_go)
        motion_tracks = movement_tracks(
            importer, animator, controller, animation_paths, transforms, by_go
        )
        gfx_go = data["GFXObject"]["m_PathID"]
        gfx_pose = spatial.sprite_plane(by_go[gfx_go], 16.0)
        death_tracks = []
        for index, state in enumerate(states):
            if state_names.get(state["data"]["m_NameID"], "").endswith("_Dead"):
                death_tracks.extend(
                    animator_tracks(importer, animator, animation_paths, transforms, by_go, index)
                )

        enemies.append(
            dict(
                source_id=obj.path_id,
                go=go,
                kind=kind,
                position=root_pose["transform"][4:6],
                bounds_offset=bounds_offset,
                bounds_size=[
                    abs(matrix[0]) * body["m_Size"]["x"] * 16.0,
                    abs(matrix[3]) * body["m_Size"]["y"] * 16.0,
                ],
                visuals=visual_ids,
                primary_visual=read(data["GFX"])["m_GameObject"]["m_PathID"],
                facing=1 if transforms[by_go[go]]["m_LocalScale"]["x"] >= 0 else -1,
                gfx_position=gfx_pose["transform"][4:6],
                gfx_visuals=sorted(
                    set(target_paths(gfx_go, gos, transforms, by_go).values()) & visual_gos
                ),
                profile=profile,
                common=read(data["commonEnemyProfile"]),
                invincible=bool(entity["IsInvincible"]),
                knockback=bool(entity["IsKnockBack"]),
                kunai=dict(
                    canShurikenHit=entity["ShurikenComponent"]["canShurikenHit"],
                    ignore_weak_point=entity["EnemyWeakPointComponent"]["IgnoreWeakPoint"],
                ),
                scout=bool(data["isScout"]),
                scout_distance=data["scoutDistance"],
                character_type=data["enemyCharacterType"],
                death_tracks=death_tracks,
                motion_tracks=motion_tracks,
                # Source EnemyStateMachine.Gravity and EnemyRifleMan.OnDead.
                gravity=20.0,
                corpse_fade_time=2.0,
                death_particle=data["DeadParticleName"],
            )
        )
        if kind in ("EnemyRifleMan", "EnemyBowMan", "EnemyBombMan"):
            enemies[-1]["combat_animations"] = combat_animations(
                importer, animator, controller, animation_paths, transforms, by_go
            )
        if kind in ("EnemyRifleMan", "EnemyBowMan"):
            key = "rifle_presentation" if kind == "EnemyRifleMan" else "ranged_presentation"
            enemies[-1][key] = ranged_presentation(
                importer, obj, data, gos, transforms, by_go, order
            )
    return enemies
