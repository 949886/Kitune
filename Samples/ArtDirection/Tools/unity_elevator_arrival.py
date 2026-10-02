"""Read the active elevator-arrival Timeline, excluding obsolete saved bindings."""

from unity_scene_animation import binding_width, target_paths
from unity_scene_spatial import WorldTransforms
from unity_shrine_pose import clip_channels


def export(importer, objects, gos, poses, by_go, timeline_name):
    world = WorldTransforms(poses)
    director, asset = next((o, importer.pointer(o.assets_file, o.read_typetree()["m_PlayableAsset"]).deref())
        for o in objects.values() if o.type.name == "PlayableDirector"
        and importer.pointer(o.assets_file, o.read_typetree()["m_PlayableAsset"]).read_typetree()["m_Name"] == timeline_name)
    bindings = {b["key"]["m_PathID"]: b["value"]["m_PathID"] for b in director.read_typetree()["m_SceneBindings"]}
    module = next(o for o in objects.values() if o.type.name == "MonoBehaviour"
        and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "TimelineModulePlayer"
        and o.read_typetree()["m_GameObject"] == director.read_typetree()["m_GameObject"])
    setting = module.read_typetree()
    assert setting["IsAutoPlay"] and setting["IsOnece"] and not setting["CanSkip"]
    dynamic = importer.pointer(module.assets_file, setting["timelineInGameBindingData"]).read_typetree()["BindingDatas"]
    dynamic = {p["m_PathID"]: v for p, v in zip(dynamic["keys"], dynamic["values"])}
    result = {"name": timeline_name, "tracks": [], "audio": [], "unsupported": [], "extra_visuals": [],
              "source_file": asset.assets_file.name, "source_asset": asset.path_id}

    def descendants(go):
        return sorted(set(target_paths(go, gos, poses, by_go).values()))

    def visit(pointer):
        obj = importer.pointer(asset.assets_file, pointer).deref()
        tree = obj.read_typetree()
        if tree.get("m_Muted"):
            return
        kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
        for pointer in tree.get("m_Children", []):
            visit(pointer)
        if kind == "InGameCommandSignalTrack":
            for pointer in tree["m_Markers"]["m_Objects"]:
                marker = importer.pointer(obj.assets_file, pointer).deref()
                data = marker.read_typetree()
                command = importer.pointer(marker.assets_file, data["Command"]).read_typetree()
                assert command["m_Name"] == "TimelineCompleteCommand"
                result["duration"] = data["m_Time"]
        for clip in tree.get("m_Clips", []):
            if kind == "FMODEventTrack":
                groups = {"Elevator": "elevator", "Elevator_Steam": "elevator_steam"}
                result["audio"].append({"start": clip["m_Start"], "duration": clip["m_Duration"],
                                        "group": groups[clip["m_DisplayName"]]})
                continue
            assert kind == "AnimationTrack", kind
            playable = importer.pointer(obj.assets_file, clip["m_Asset"]).deref()
            offset = playable.read_typetree()
            native = importer.pointer(playable.assets_file, offset["m_Clip"]).read_typetree()
            channels, index = clip_channels(native), 0
            binding = bindings.get(obj.path_id, 0)
            is_player = not binding and dynamic.get(obj.path_id) == {"ListenerName": "Player", "BindingName": "PhysicalBinding"}
            assert binding or is_player
            root = objects[binding].read_typetree()["m_GameObject"]["m_PathID"] if binding else None
            paths = target_paths(root, gos, poses, by_go) if root else {0: None}
            for curve in native["m_ClipBindingConstant"]["genericBindings"]:
                width = binding_width(curve)
                axes = [channels[index + n] for n in range(width)]
                index += width
                target = paths.get(curve["path"])
                if curve["typeID"] == 4 and curve["attribute"] in (1, 4):
                    tid = by_go[target] if target else None
                    initial = poses[tid]["m_LocalPosition"] if target else {"x": 0, "y": 0, "z": 0}
                    parent = poses[tid]["m_Father"]["m_PathID"] if target else 0
                    targets = descendants(target) if target else []
                    result["extra_visuals"].extend(targets)
                    result["tracks"].append({"go": target, "children": targets, "player": is_player,
                        "kind": "position" if curve["attribute"] == 1 else "rotation",
                        "initial": [initial[a] for a in "xyz"], "parent": world.sprite_plane(parent, 16)["transform"],
                        "offset": [offset["m_Position"][a] + tree["m_Position"][a] for a in "xyz"],
                        "axes": axes, "start": clip["m_Start"], "duration": clip["m_Duration"],
                        "clip_in": clip["m_ClipIn"], "speed": clip["m_TimeScale"],
                        "length": native["m_MuscleClip"]["m_StopTime"], "track": obj.path_id})
                else:
                    result["unsupported"].append({"track": obj.path_id, "clip": native["m_Name"], "binding": curve})

    for pointer in asset.read_typetree()["m_Tracks"]:
        visit(pointer)
    save = next(o.read_typetree() for o in objects.values() if o.type.name == "MonoBehaviour"
                and o.parse_monobehaviour_head().m_Script.read().m_ClassName == "TimelineSaveMoudle")
    result["saved_spawn"] = world.sprite_plane(save["spawnPoint"]["m_PathID"], 16)["transform"][4:]
    result["extra_visuals"] = sorted(set(result["extra_visuals"]))
    assert result.get("duration", 0) > 0
    return result
