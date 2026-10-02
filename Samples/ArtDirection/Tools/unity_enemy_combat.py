"""Original ranged-enemy animation graphs and initially hidden aiming renderers."""

import math
from unity_scene_animation import animator_tracks, target_paths


def ranged_visuals(importer, objects, gos, transforms, by_go, active):
    result = set()
    for obj in objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if head.m_Script.read().m_ClassName not in ("EnemyRifleMan", "EnemyBowMan"):
            continue
        if not active(by_go[head.m_GameObject.path_id]):
            continue
        rotation = obj.read_typetree()["rotationPart"]
        for key in ("RotationHolder", "NonRotationHolder"):
            go = rotation[key]["m_PathID"]
            result.update(target_paths(go, gos, transforms, by_go).values())
    return result


def combat_animations(importer, animator, controller, paths, transforms, by_go):
    names = dict(controller["m_TOS"])
    machine = controller["m_Controller"]["m_StateMachineArray"][0]["data"]
    result = {}
    for transition in machine["m_AnyStateTransitionConstantArray"]:
        transition = transition["data"]
        conditions = [item["data"] for item in transition["m_ConditionConstantArray"]]
        trigger = next(
            (names.get(c["m_EventID"]) for c in conditions if c["m_ConditionMode"] == 1), None
        )
        if not trigger:
            continue
        indices = [c for c in conditions if names.get(c["m_EventID"]) == "Index"]
        # AnimatorConditionMode.Equals is 6 and NotEqual is 7. Preserve the
        # serialized predicates: Index 0 shoots; Index 1 selects melee/kick.
        assert all(c["m_ConditionMode"] in (6, 7) for c in indices)
        index_values = [
            i
            for i in (0, 1)
            if all(
                (
                    i != c["m_EventThreshold"]
                    if c["m_ConditionMode"] == 7
                    else i == c["m_EventThreshold"]
                )
                for c in indices
            )
        ]
        state_id = transition["m_DestinationState"]
        state = machine["m_StateConstantArray"][state_id]["data"]
        nodes = [
            n["data"]
            for tree in state["m_BlendTreeConstantArray"]
            for n in tree["data"]["m_NodeArray"]
        ]
        if not nodes:
            continue
        info = {"name": names[state["m_NameID"]], "state_id": state_id, "conditions": conditions}
        if nodes[0]["m_ChildIndices"]:
            root = nodes[0]
            assert root["m_BlendType"] == 0, "Only original 1D angle trees are supported"
            info["parameter"] = names[root["m_BlendEventID"]]
            info["variants"] = [
                {
                    "threshold": threshold,
                    "tracks": animator_tracks(
                        importer,
                        animator,
                        paths,
                        transforms,
                        by_go,
                        state_id,
                        nodes[child]["m_ClipID"],
                    ),
                }
                for threshold, child in zip(
                    root["m_Blend1dData"]["data"]["m_ChildThresholdArray"], root["m_ChildIndices"]
                )
            ]
        else:
            info["tracks"] = animator_tracks(importer, animator, paths, transforms, by_go, state_id)
        for index in index_values:
            result[f"{trigger}:{index}"] = info
    return result


def ranged_presentation(importer, obj, data, gos, transforms, by_go, order):
    rotation = data["rotationPart"]
    result = {
        key: rotation[key] for key in ("rotationScale", "rotationOffset", "hasNonRotationHolder")
    }
    result["holder_defaults"] = {}
    for key in ("RotationHolder", "NonRotationHolder"):
        root_go = rotation[key]["m_PathID"]
        result[key] = sorted(target_paths(root_go, gos, transforms, by_go).values())
        for go in result[key]:
            current, enabled = go, True
            while current != root_go:
                enabled = enabled and bool(gos[current]["m_IsActive"])
                parent = transforms[by_go[current]]["m_Father"]["m_PathID"]
                current = transforms[parent]["m_GameObject"]["m_PathID"]
            result["holder_defaults"][str(go)] = enabled
    for key in ("RotationSpriteInfos", "NonRotationHolderInfos"):
        entries = []
        for reference, source in zip(rotation[key]["keys"], rotation[key]["values"]):
            renderer = importer.pointer(obj.assets_file, reference).read_typetree()
            go = renderer["m_GameObject"]["m_PathID"]
            q = transforms[by_go[go]]["m_LocalRotation"]
            entries.append(
                {
                    "go": go,
                    "scale": source["RotationScale"],
                    "initial_angle": math.degrees(2 * math.atan2(q["z"], q["w"])),
                    "infos": [
                        {
                            "sprite": importer.sprite(
                                importer.pointer(obj.assets_file, info["Sprite"])
                            ),
                            "angle": info["Angle"],
                            "order": info["OrderInLayer"],
                            "sort": order(
                                go,
                                dict(
                                    renderer,
                                    m_SortingOrder=info["OrderInLayer"]
                                    or renderer["m_SortingOrder"],
                                ),
                            ),
                        }
                        for info in source["Infos"]
                    ],
                }
            )
        result[key] = entries
    return result
