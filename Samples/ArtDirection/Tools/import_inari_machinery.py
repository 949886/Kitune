"""Append native machinery scenes and animation states without replacing calibrated assets.

Scene parsing runs into an ignored staging directory. Existing sprite records and
material definitions remain authoritative for old levels; new scenes namespace
their material references and new pixels receive individually hashed PNGs.
"""

import argparse
import copy
import hashlib
import json
import shutil
import re
from pathlib import Path

from import_inari import Importer, UnityPy, dump, PIXELS_PER_UNIT, rgba
from import_inari_arrow import save_pixels
from unity_scene_animation import animator_tracks, target_paths
from unity_scene_spatial import WorldTransforms
from unity_mechanism_animation import controller as mechanism_controller
from unity_elevator_arrival import export as arrival_timeline
from unity_scene_trials import prepare as prepare_trials, bind_lights as bind_trial_lights
from unity_scene_battle import prepare as prepare_battle, finish as finish_battle


def export(source, root):
    output = root / "Original/INARI"
    staging = root.parents[1] / "tmp/art-direction/machinery-import"
    staging.mkdir(parents=True, exist_ok=True)
    original_sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    materials = json.loads((output / "materials.json").read_text(encoding="utf8"))
    # Re-read owned pixels on every import, while retaining all earlier imports.
    retained = {k: v for k, v in original_sprites.items() if not v.get("path", "").startswith("Machinery/")}
    importer = Importer(source, staging)
    importer.sprites = copy.deepcopy(retained)
    catalog = json.loads((output / "mechanism_catalog.json").read_text(encoding="utf8"))
    selection = json.loads((root / "Profiles/mechanism_levels.json").read_text(encoding="utf8"))
    result = {"levels": {}, "source_sha256": {}}
    build = next(o.read_typetree()["scenes"] for o in UnityPy.load(str(source / "globalgamemanagers")).objects if o.type.name == "BuildSettings")
    resources = UnityPy.load(str(source / "resources.assets"))
    guid_map = json.loads(next(o.read().m_Script for o in resources.objects if o.type.name == "TextAsset" and o.read().m_Name == "Eflatun_SceneReference_SceneGuidToPathMap.generated"))
    for number in selection["scenes"]:
        scene = f"level{number}"
        env = UnityPy.load(str(source / scene))
        env.typetree_generator = importer.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == scene}
        poses = {i: o.read_typetree() for i, o in objects.items() if o.type.name in ("Transform", "RectTransform")}
        gos = {i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"}
        by_go = {p["m_GameObject"]["m_PathID"]: i for i, p in poses.items()}
        entries = {int(e["component_id"]): e for e in catalog["scenes"][scene]}
        platforms, levers, elevators, scene_moves, ice_boxes = [], [], [], [], []
        world = WorldTransforms(poses)

        def descendants(go):
            return sorted(set(target_paths(go, gos, poses, by_go).values()))

        def animation(pointer):
            return mechanism_controller(importer, objects.get(pointer["m_PathID"]), gos, poses, by_go)

        def box(pointer):
            value = objects[pointer["m_PathID"]].read_typetree()
            go = value["m_GameObject"]["m_PathID"]
            return {"go": go, "transform": world.sprite_plane(by_go[go], PIXELS_PER_UNIT)["transform"],
                    "size": [value["m_Size"][a] * PIXELS_PER_UNIT for a in "xy"],
                    "offset": [value["m_Offset"]["x"] * PIXELS_PER_UNIT, -value["m_Offset"]["y"] * PIXELS_PER_UNIT],
                    "enabled": bool(value["m_Enabled"]), "is_trigger": value["m_IsTrigger"]}

        for entry in entries.values():
            if not entry["active"] or not entry["enabled"]:
                continue
            fields = entry["fields"]
            go = int(entry["go"])
            if entry["type"] == "ElectroBox":
                collider_id = next(c["component_id"] for c in entry["colliders"] if c["type"] == "BoxCollider2D")
                manager = next(o.read_typetree() for o in objects.values() if o.type.name == "MonoBehaviour"
                    and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "TileMapPathManager")
                tilemap = objects[manager["tileMap"][0]["m_PathID"]].read_typetree()
                grid = objects[manager["tileMapGrid"]["m_PathID"]].read_typetree()
                assert grid["m_CellLayout"] == 0 and grid["m_CellSwizzle"] == 0
                assert all(grid["m_CellSize"][a] == 1 and grid["m_CellGap"][a] == 0 for a in 'xy')
                renderer = objects[fields["spriteRenderer"]["m_PathID"]]
                mat = importer.pointer(renderer.assets_file, renderer.read_typetree()["m_Materials"][0]).read_typetree()
                floats = dict(mat["m_SavedProperties"]["m_Floats"])
                colors = dict(mat["m_SavedProperties"]["m_Colors"])
                assert "OUTBASE_ON" in mat["m_ValidKeywords"]
                ice_boxes.append({"outline": {"color": rgba(colors["_OutlineColor"]), "alpha": floats["_OutlineAlpha"],
                    "glow": floats["_OutlineGlow"], "width": floats["_OutlineWidth"],
                    "pixel_perfect": "OUTBASEPIXELPERF_ON" in mat["m_ValidKeywords"], "pixel_width": floats["_OutlinePixelWidth"]}, "go": go, "fields": fields, "collider": box({"m_PathID": int(collider_id)}),
                    "animation": animation(fields["ani"]),
                    "renderer_go": objects[fields["spriteRenderer"]["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"],
                    "grid_transform": world.sprite_plane(by_go[tilemap["m_GameObject"]["m_PathID"]], PIXELS_PER_UNIT)["transform"],
                    "cell_size": PIXELS_PER_UNIT,
                    "anchor": [tilemap["m_TileAnchor"]["x"], -tilemap["m_TileAnchor"]["y"]]})
            if entry["type"] == "SceneMoveTrigger":
                obj = objects[int(entry["component_id"])]
                reference = importer.pointer(obj.assets_file, fields["sceneReferenceData"]).read_typetree()
                scene_path = guid_map[reference["SceneReference"]["guid"]]
                destination = build.index(scene_path)
                collider_id = next(c["component_id"] for c in entry["colliders"] if c["type"] == "BoxCollider2D")
                scene_moves.append({"go": go, "trigger": box({"m_PathID": int(collider_id)}),
                    "fields": fields, "destination": f"level{destination}.json", "scene_path": scene_path,
                    "available": destination in selection["scenes"], "scene_reference": reference})
            if entry["type"] in ("PlatformController", "ElevatorPlatform"):
                assert fields["lightEasing"] == 27, "Runtime light tween expects source OutBack"
                collider = next(c["data"] for c in entry["colliders"] if c["type"] == "CompositeCollider2D")
                assert collider["m_Enabled"] and not collider["m_IsTrigger"]
                paths = [[[p["x"] * PIXELS_PER_UNIT, -p["y"] * PIXELS_PER_UNIT] for p in path]
                         for path in collider["m_CompositePaths"]["m_Paths"]]
                platforms.append({"id": entry["component_id"], "go": go, "type": entry["type"],
                    "transform": entry["spatial"]["transform"], "fields": fields,
                    "waypoints": [[v["x"] * PIXELS_PER_UNIT, -v["y"] * PIXELS_PER_UNIT] for v in fields["LocalWaypoints"]],
                    "paths": paths, "children": descendants(go),
                    "wheels": [p["m_PathID"] for p in fields["wheels"] if p["m_PathID"]],
                    "lights": [objects[p["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"] for p in fields["Lights"]]})
                if entry["type"] == "ElevatorPlatform":
                    platforms[-1].update(start_animation=animation(fields["startAnimator"]),
                                         end_animation=animation(fields["endAnimator"]))
            elif entry["type"] == "InteractableObjectTrigger":
                assert fields["triggerType"] == 1, "Reward objects require their own gameplay adapter"
                assert not fields["once"]
                assert all(not fields[key]["m_PersistentCalls"]["m_Calls"] for key in ("enterEvent", "exitEvent", "loadEvent"))
                targets = []
                for pointer in fields["elevators"]:
                    observer = entries[pointer["m_PathID"]]
                    assert observer["type"] == "PlatformControllerObserver"
                    targets.append(str(observer["fields"]["platformController"]["m_PathID"]))
                elevators.append({"go": go, "fields": fields, "targets": targets,
                    "trigger": box(fields["coll"]), "doors": [box(p) for p in fields["doorColliders"]],
                    "button_animation": animation(fields["animator"]),
                    "door_animation": animation(fields["doorAnimator"]), "children": descendants(go)})
            elif entry["type"] == "InteractableTrigger":
                targets = []
                for observer in fields["observers"]:
                    target = entries[observer["m_PathID"]]
                    assert target["type"] == "PlatformControllerObserver", target["type"]
                    targets.append(str(target["fields"]["platformController"]["m_PathID"]))
                collider = objects[fields["coll"]["m_PathID"]].read_typetree()
                animator = objects[fields["ani"]["m_PathID"]]
                controller = animator.read().m_Controller.read_typetree()
                names = dict(controller["m_TOS"])
                machine = controller["m_Controller"]["m_StateMachineArray"][0]["data"]
                paths = target_paths(animator.read().m_GameObject.path_id, gos, poses, by_go)
                states = {names[state["data"]["m_NameID"]]: animator_tracks(importer, animator, paths, poses, by_go, selected_state=i)
                          for i, state in enumerate(machine["m_StateConstantArray"])}
                levers.append({"go": go, "transform": entry["spatial"]["transform"], "fields": fields,
                    "targets": targets, "states": states, "default_state": names[machine["m_StateConstantArray"][machine["m_DefaultState"]]["data"]["m_NameID"]],
                    "children": descendants(go), "size": [collider["m_Size"][a] * PIXELS_PER_UNIT for a in "xy"],
                    "offset": [collider["m_Offset"]["x"] * PIXELS_PER_UNIT, -collider["m_Offset"]["y"] * PIXELS_PER_UNIT]})
        extra_visuals = {go for entry in platforms + levers for go in entry["children"]}
        extra_visuals.update(go for ice in ice_boxes for go in ice["animation"]["children"])
        arrival = {}
        if scene in selection.get("arrival_timelines", {}):
            arrival = arrival_timeline(importer, objects, gos, poses, by_go, selection["arrival_timelines"][scene])
            extra_visuals.update(arrival["extra_visuals"])
            asset_file = arrival["source_file"]
            result["source_sha256"][asset_file] = hashlib.sha256((source / asset_file).read_bytes()).hexdigest()
        for platform in platforms:
            for key in ("start_animation", "end_animation"):
                extra_visuals.update(platform.get(key, {}).get("children", []))
        battle, forced, bindings = {}, set(), {}
        if number in selection.get('battle_scenes', []):
            battle, forced, battle_visuals, bindings = prepare_battle(importer, objects, gos, poses, by_go, entries, box, animation)
            extra_visuals.update(battle_visuals)
        trials = {}
        if number in selection.get('trial_scenes', []):
            trials, trial_visuals = prepare_trials(importer, objects, gos, poses, by_go, entries, box, animation)
            extra_visuals.update(trial_visuals)
        importer.scene(number, extra_visuals=extra_visuals, active_roots=forced)
        data = json.loads((staging / f"{scene}.json").read_text(encoding="utf8"))
        bind_trial_lights(trials, data)
        if battle:
            finish_battle(importer, data, bindings)
        # Replace the old tile-based approximation with the shipped composite.
        dynamic_gos = {go for p in platforms for go in p["children"]} | {p["go"] for p in levers}
        controlled_gos = {b["go"] for e in elevators for b in e["doors"] + [e["trigger"]]}
        for platform in platforms:
            platform["child_colliders"] = [c for c in data["colliders"]
                if c.get("go") in platform["children"] and c.get("go") != platform["go"]
                and c.get("go") not in controlled_gos]
        data["colliders"] = [c for c in data["colliders"] if c.get("go") not in dynamic_gos and c.get("go") not in {ice["go"] for ice in ice_boxes}]
        battle_gos = {c['go'] for door in battle.get('doors', []) for c in door['colliders']}
        data['colliders'] = [c for c in data['colliders'] if c.get('go') not in battle_gos]
        prefix = scene + "/"

        def namespace(value):
            if isinstance(value, list):
                return [namespace(v) for v in value]
            if isinstance(value, dict):
                result = {k: namespace(v) for k, v in value.items()}
                if isinstance(value.get("material"), str) and value["material"]:
                    result["material"] = prefix + value["material"]
                if value.get("kind") == "material":
                    result["frames"] = [[t, prefix + name if name else name] for t, name in value["frames"]]
                return result
            return value

        data = namespace(data)
        result["levels"][scene] = namespace({"platforms": platforms, "levers": levers, "elevators": elevators, "scene_moves": scene_moves, "arrival": arrival, 'battle': battle, 'ice_boxes': ice_boxes, 'trials': trials})
        for name, material in importer.material_details.items():
            # Later scene-local supplements must not mutate earlier namespaces
            # through shared dictionaries (e.g. the battle enemy outlines).
            materials[prefix + name] = copy.deepcopy(material)
        dump(output / f"{scene}.json", data)
        result["source_sha256"][scene] = hashlib.sha256((source / scene).read_bytes()).hexdigest()
        print(scene, "platforms", len(platforms), "levers", len(levers), "elevators", len(elevators), flush=True)
    directory = output / "Machinery"
    directory.mkdir(exist_ok=True)
    for key, image in sorted(importer.images.items()):
        info = save_pixels(image, directory, key + ".png")
        info["path"] = "Machinery/" + info["path"]
        info["region"] = [0, 0, image.width, image.height]
        importer.sprites[key].update(info)
    # Existing sprite metadata must not change because a later scene happens to
    # use the same sprite with another effect mesh or material.
    importer.sprites.update(retained)
    for path in (staging / "Textures").glob("*.png"):
        destination = output / "Textures" / path.name
        if not destination.exists():
            shutil.copy2(path, destination)
    decompiled = root.parents[1] / "tmp/art-direction/decompiled"
    elevator_code = (decompiled / "InteractableObjectTrigger.cs").read_text(encoding="utf8")
    delay = re.search(r"DeferredColliderDisable\(\).*?new WaitForSeconds\(([\d.]+)f\)", elevator_code, re.S)
    assert delay
    result["elevator_rules"] = {"door_release_delay": float(delay[1])}
    spawn_code = (decompiled / 'SpawnManager.cs').read_text(encoding='utf8')
    spawn_delay = re.search(r'SpawnRoutine\(.*?new WaitForSeconds\(([\d.]+)f\)', spawn_code, re.S)
    assert spawn_delay
    result['battle_rules'] = {'spawn_delay': float(spawn_delay[1])}
    for name in ['Door.cs', 'DoorContactTrigger.cs', 'MonsterSpawnerTrigger.cs', 'SpawnManager.cs', 'Observer.cs', 'Trigger.cs', 'Enemy.StateMachine/EnemyStateMachine.cs']:
        result['source_sha256'][name] = hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
    persistent = UnityPy.load(str(source / "level1"))
    persistent.typetree_generator = importer.generator
    ui = next(o.read_typetree() for o in persistent.objects if o.type.name == "MonoBehaviour"
              and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "SceneTranslationUI")
    result["scene_rules"] = {"fade_duration": ui["translationImageDuration"]}
    for name in ["globalgamemanagers", "resources.assets", "level1"]:
        result["source_sha256"][name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
    for name in ["PlatformController.cs", "RaycastCollision2D.cs", "InteractableTrigger.cs", "PlatformControllerObserver.cs", "ObjectInGameEntity.cs", "ObjectShurikenComponent.cs", "ShurikenObject.cs", "ElevatorPlatform.cs", "InteractableObjectTrigger.cs", "PlayerStateMachine.cs", "SceneMoveTrigger.cs", "SceneTranslationManager.cs", "SceneTranslationUI.cs", "GameManager.cs"]:
        result["source_sha256"][name] = hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
    for name in ["TimelineModulePlayer.cs", "BaseTimelinePlayer.cs", "TimelineCompleteCommand.cs", "Resources.Scripts.Timeline.Player/TimelineSaveMoudle.cs"]:
        result["source_sha256"][name] = hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
    ice_code = (decompiled / 'ElectroBox.cs').read_text(encoding='utf8')
    loop_distance = re.search(r'Distance\(.*?< ([\d.]+)f', ice_code)
    flood_box = re.search(r'Vector2.one \* ([\d.]+)f', ice_code)
    assert loop_distance and flood_box
    result['ice_rules'] = {'loop_distance': float(loop_distance[1]), 'flood_box_size': float(flood_box[1]),
        'blocking_layers': ['Ground', 'HardWall', 'Door', 'Wall', 'InteractiveWall']}
    charge_code = (decompiled / 'ShurikenChargePoint.cs').read_text(encoding='utf8')
    result['trial_rules'] = {
        'charge_max_speed': float(re.search(r'maxSpeed = ([\d.]+)f', charge_code)[1]),
        'charge_min_time': float(re.search(r'homingProgress > ([\d.]+)f', charge_code)[1]),
        'charge_value': int(re.search(r'ChargedMoneyPoint\((\d+)\)', charge_code)[1])}
    for name in ['TimeAttackTrigger.cs', 'TimeAttackTriggerDest.cs', 'TimeAttackTimerBase.cs', 'RewardObserver.cs', 'ShurikenChargePoint.cs', 'SimpleAnimator.cs', 'ElectroBox.cs', 'ShurikenComponent.cs', 'WeakPointComponent.cs', 'Enemy.State/HitState.cs', 'DHUtil.RunTime/CoroutinUtil.cs']:
        result['source_sha256'][name] = hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
    dump(output / "sprites.json", importer.sprites)
    dump(output / "materials.json", materials)
    dump(output / "machinery.json", result)
    print("New original sprite frames:", len(importer.images))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1])
