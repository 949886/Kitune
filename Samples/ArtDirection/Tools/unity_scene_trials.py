"""Export authored timer endpoints, camera stops and reward UnityEvent wiring."""

import copy
import zlib
from unity_scene_animation import simple_tracks, target_paths
from import_inari import rgba
from import_inari_particles import portable
from unity_scene_spatial import WorldTransforms


def prepare(importer, objects, gos, poses, by_go, entries, box, animation):
    world = WorldTransforms(poses)
    timers, rewards, visuals = [], [], set()

    def material(pointer):
        renderer = objects[pointer["m_PathID"]]
        return importer.pointer(
            renderer.assets_file, renderer.read_typetree()["m_Materials"][0]
        ).read_typetree()

    def renderer_go(pointer):
        return objects[pointer["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"]

    for entry in entries.values():
        if not entry["active"] or not entry["enabled"]:
            continue
        fields = entry["fields"]
        if entry["type"] in ("TimeAttackTrigger", "TimeAttackTriggerDest"):
            assert fields["triggerLayer"]["m_Bits"] == 64
            assert all(
                not fields[k]["m_PersistentCalls"]["m_Calls"]
                for k in ["enterEvent", "exitEvent", "loadEvent"]
            )
            controller = animation(fields["ani"])
            visuals.update(controller["children"])
            record = {
                "id": int(entry["component_id"]),
                "go": int(entry["go"]),
                "kind": entry["type"],
                "fields": fields,
                "trigger": box(fields["coll"]),
                "animation": controller,
                "digits": [
                    {
                        "go": renderer_go(p),
                        "floats": dict(material(p)["m_SavedProperties"]["m_Floats"]),
                    }
                    for p in fields["renders"]
                ],
                "outlines": [],
            }
            for pointer in fields["sprites"]:
                mat = material(pointer)
                floats = dict(mat["m_SavedProperties"]["m_Floats"])
                colors = dict(mat["m_SavedProperties"]["m_Colors"])
                record["outlines"].append(
                    {
                        "go": renderer_go(pointer),
                        "color": rgba(colors["_OutlineColor"]),
                        "alpha": floats["_OutlineAlpha"],
                        "glow": floats["_OutlineGlow"],
                        "width": floats["_OutlineWidth"],
                        "pixel_width": floats["_OutlinePixelWidth"],
                        "pixel_perfect": "OUTBASEPIXELPERF_ON" in mat["m_ValidKeywords"],
                    }
                )
            if entry["type"] == "TimeAttackTrigger":
                record["camera_stops"] = [
                    dict(
                        position=world.sprite_plane(p["Transform"]["m_PathID"], 16)["transform"][
                            4:
                        ],
                        distance=p["Distance"],
                        wait=p["WaitTime"],
                    )
                    for p in fields["camTargets"]
                ]
            if entry["type"] == "TimeAttackTriggerDest":
                record["checkpoint_go"] = int(
                    entries[fields["interactiveSaveTrigger"]["m_PathID"]]["go"]
                )
            timers.append(record)
        elif entry["type"] == "Trigger":
            calls = fields["enterEvent"]["m_PersistentCalls"]["m_Calls"]
            if not any(
                call["m_TargetAssemblyTypeName"].startswith("RewardObserver,") for call in calls
            ):
                continue
            assert fields["once"] and fields["triggerLayer"]["m_Bits"] == 64
            tracks, children, cached = [], set(), []
            for call in calls:
                assert call["m_CallState"] == 2
                if call["m_TargetAssemblyTypeName"].startswith("SimpleAnimator,"):
                    assert call["m_MethodName"] == "Play" and call["m_Mode"] == 5
                    obj = objects[call["m_Target"]["m_PathID"]]
                    raw = copy.deepcopy(obj.read_typetree())
                    raw["defaultStateName"] = call["m_Arguments"]["m_StringArgument"]
                    tracks.extend(simple_tracks(importer, obj, raw))
                    paths = target_paths(raw["m_GameObject"]["m_PathID"], gos, poses, by_go)
                    children.update(paths.values())
                    state = portable(
                        next(
                            s
                            for s in raw["cachedStates"]
                            if s["stateName"] == raw["defaultStateName"]
                        )
                    )
                    for curve in state["curves"] + state["gameObjectActives"]:
                        curve["go"] = paths[zlib.crc32(curve["path"].encode("utf8"))]
                    cached.append(
                        {
                            "go": raw["m_GameObject"]["m_PathID"],
                            "paths": paths,
                            "speed": raw["animationSpeed"],
                            "ignore_position": raw["ignorePositionControl"],
                            "state": state,
                        }
                    )
                else:
                    assert (
                        call["m_TargetAssemblyTypeName"].startswith("RewardObserver,")
                        and call["m_MethodName"] == "OnEventNotify"
                    )
            charges, lights = [], []
            for go in children:
                for component in gos[go]["m_Component"]:
                    obj = objects[component["component"]["m_PathID"]]
                    if obj.type.name != "MonoBehaviour":
                        continue
                    kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
                    if kind == "ShurikenChargePoint":
                        charges.append({"go": go, "fields": obj.read_typetree()})
                    elif kind == "Light2D":
                        raw = obj.read_typetree()
                        lights.append(
                            {
                                "go": go,
                                "order": raw["m_LightOrder"],
                                "transform": world.sprite_plane(by_go[go], 16)["transform"],
                            }
                        )
            collider = next(c for c in entry["colliders"] if c["type"] == "BoxCollider2D")
            visuals.update(children)
            rewards.append(
                {
                    "id": int(entry["component_id"]),
                    "go": int(entry["go"]),
                    "fields": fields,
                    "trigger": box({"m_PathID": int(collider["component_id"])}),
                    "tracks": tracks,
                    "cached": cached,
                    "children": sorted(children),
                    "charges": sorted(charges, key=lambda x: x["go"]),
                    "lights": lights,
                }
            )
    return {"timers": timers, "rewards": rewards}, visuals


def bind_lights(trials, scene):
    """Bind light dictionary indices from original order/pose, never a level ID map."""
    for reward in trials.get("rewards", []):
        for source in reward["lights"]:
            matches = [
                i
                for i, light in enumerate(scene["lights"])
                if light["settings"]["order"] == source["order"]
                and light["spatial"]["transform"] == source["transform"]
            ]
            assert len(matches) == 1, source
            source["index"] = matches[0]
