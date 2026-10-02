"""Resolve native combat-room door subscriptions and serialized enemy waves."""

from unity_enemy_bindings import collect as enemy_bindings
from unity_scene_animation import target_paths


def prepare(importer, objects, gos, poses, by_go, entries, box, animation):
    result = {"doors": [], "contacts": [], "spawners": [], "spawn_triggers": []}
    forced, visuals, actors = set(), set(), set()
    for entry in entries.values():
        if not entry["active"] or not entry["enabled"]:
            continue
        fields = entry["fields"]
        if entry["type"] == "Door":
            assert all(not fields[k]["m_PersistentCalls"]["m_Calls"] for k in ["onOpen", "onClose"])
            anim = animation(fields["animator"])
            colliders = []
            for pointer in fields["doorColliders"]:
                collider = box(pointer)
                collider["id"] = pointer["m_PathID"]
                colliders.append(collider)
            result["doors"].append(
                {
                    "id": int(entry["component_id"]),
                    "go": int(entry["go"]),
                    "fields": fields,
                    "animation": anim,
                    "colliders": colliders,
                }
            )
            visuals.update(anim["children"])
        elif entry["type"] in ["DoorContactTrigger", "MonsterSpawnerTrigger"]:
            assert fields["triggerLayer"]["m_Bits"] == 64
            assert all(
                not fields[k]["m_PersistentCalls"]["m_Calls"]
                for k in ["enterEvent", "exitEvent", "loadEvent"]
            )
            pointer = fields.get("collider") or {
                "m_PathID": int(
                    next(
                        c["component_id"]
                        for c in entry["colliders"]
                        if c["type"] == "BoxCollider2D"
                    )
                )
            }
            record = {"id": int(entry["component_id"]), "fields": fields, "trigger": box(pointer)}
            result[
                "contacts" if entry["type"] == "DoorContactTrigger" else "spawn_triggers"
            ].append(record)
    for obj in objects.values():
        if (
            obj.type.name != "MonoBehaviour"
            or obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "SpawnManager"
        ):
            continue
        raw = obj.read_typetree()
        assert (
            not raw["timeLine"]["m_PathID"]
        ), "Ending cutscenes need explicit adapters"
        for phase in raw["spawnDatas"]:
            forced.add(phase["Phase"]["m_PathID"])
            for pointer in phase["EnemyPrefab"]:
                actor = objects[pointer["m_PathID"]]
                go = actor.read_typetree()["m_GameObject"]["m_PathID"]
                actors.add(actor.path_id)
                forced.add(go)
                assert actor.parse_monobehaviour_head().m_Script.read().m_ClassName in [
                    "EnemyRifleMan",
                    "EnemyBowMan",
                    "EnemyBombMan",
                ]
                visuals.update(target_paths(go, gos, poses, by_go).values())
        result["spawners"].append({"id": obj.path_id, "fields": raw})
    bindings, additional = enemy_bindings(importer, objects, gos, poses, by_go, actors)
    visuals.update(additional)
    return result, forced, visuals, bindings


def finish(importer, scene, bindings):
    visible = {s["go"] for s in scene["sprites"]}
    for actor in scene["enemies"]:
        if actor["go"] not in bindings:
            continue
        for name, outline in bindings[actor["go"]].pop("outline_materials").items():
            importer.material_details[name]["base_outline"] = outline
        actor.update(bindings[actor["go"]])
        weak = actor["weakpoint_binding"]
        weak["stacks"] = [[go for go in stack if go in visible] for stack in weak["stacks"]]
        weak["range_members"] = [go for go in weak["range_members"] if go in visible]
