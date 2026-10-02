"""Inventory interactable components in every installed scene, including inactive ones.

Discovery follows source inheritance and physics callbacks rather than a hand-picked
list of familiar props. Serialized fields and UnityEvent references remain intact so
subsequent ports can resolve actual wiring instead of guessing from object names.
"""

import argparse
import hashlib
import re
from collections import Counter
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, dump, PIXELS_PER_UNIT
from unity_scene_spatial import WorldTransforms


def source_types(directory):
    result = {}
    for path in sorted(directory.rglob("*.cs")):
        code = path.read_text(encoding="utf-8-sig")
        match = re.search(r"public (?:abstract |sealed )?class (\w+)(?:\s*:\s*([^\n{]+))?", code)
        if match:
            result[match[1]] = {
                "base": (match[2] or "").split(",")[0].strip(),
                "path": path.relative_to(directory).as_posix(),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "physics_callback": bool(re.search(r"void On(?:Trigger|Collision)(?:Enter|Stay|Exit)2D\(", code)),
                "physics_overlap": bool(re.search(r"Physics2D\.Overlap\w*\(", code)),
            }
    # Event sources can react indirectly, without their own physics callback.
    # SpawnManager, for example, opens subscribed doors after the final death.
    roots = {"Trigger", "ObjectInGameEntity", "PlatformController", "Observer", "MonoSubject"}

    def candidate(name, seen=None):
        seen = set() if seen is None else seen
        if name in seen or name not in result:
            return False
        seen.add(name)
        item = result[name]
        return name in roots or item["physics_callback"] or item["physics_overlap"] or name.endswith("Trigger") or candidate(item["base"], seen)

    return {name: item for name, item in result.items() if candidate(name)}


def export(source, decompiled, output):
    types = source_types(decompiled)
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    scenes = {}
    hashes = {"Managed/Assembly-CSharp.dll": hashlib.sha256((source / "Managed/Assembly-CSharp.dll").read_bytes()).hexdigest()}
    for path in sorted(source.glob("level*"), key=lambda p: int(p.name[5:]) if p.name[5:].isdigit() else 9999):
        if not path.name[5:].isdigit():
            continue
        env = UnityPy.load(str(path))
        env.typetree_generator = generator
        objects = list(env.objects)
        by_id = {obj.path_id: obj for obj in objects if obj.assets_file.name == path.name}
        transforms = {obj.path_id: obj.read_typetree() for obj in by_id.values() if obj.type.name == "Transform"}
        gos = {obj.path_id: obj.read_typetree() for obj in by_id.values() if obj.type.name == "GameObject"}
        by_go = {pose["m_GameObject"]["m_PathID"]: tid for tid, pose in transforms.items()}
        world = WorldTransforms(transforms)

        def hierarchy(tid):
            if not tid:
                return [], True
            pose = transforms[tid]
            parent, active = hierarchy(pose["m_Father"]["m_PathID"])
            go = gos[pose["m_GameObject"]["m_PathID"]]
            return parent + [go["m_Name"]], active and bool(go["m_IsActive"])

        instances = []
        for obj in by_id.values():
            if obj.type.name != "MonoBehaviour":
                continue
            name = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
            if name not in types:
                continue
            try:
                data = obj.read_typetree()
            except (EOFError, ValueError) as error:
                # Some Odin-serialized components cannot be decoded by the managed
                # type-tree generator. Keep the component visible in the inventory.
                header = obj.parse_monobehaviour_head()
                data = {"m_GameObject": {"m_PathID": header.m_GameObject.path_id}, "m_Enabled": header.m_Enabled,
                        "decode_error": str(error)}
                print(path.name, name, "undecoded:", error, flush=True)
            go_id = data["m_GameObject"]["m_PathID"]
            if go_id not in by_go:
                continue
            tid = by_go[go_id]
            names, active = hierarchy(tid)
            colliders = []
            for entry in gos[go_id]["m_Component"]:
                component = by_id.get(entry["component"]["m_PathID"])
                if component and component.type.name.endswith("Collider2D"):
                    colliders.append({"component_id": str(component.path_id), "type": component.type.name, "data": component.read_typetree()})
            transform_refs = {key: world.sprite_plane(value["m_PathID"], PIXELS_PER_UNIT)
                              for key, value in data.items() if isinstance(value, dict)
                              and value.get("m_FileID") == 0 and value.get("m_PathID") in transforms}
            instances.append({"component_id": str(obj.path_id), "go": str(go_id), "type": name,
                              "path": "/".join(names), "active": active, "enabled": bool(data.get("m_Enabled", True)),
                              "spatial": world.sprite_plane(tid, PIXELS_PER_UNIT), "transform_refs": transform_refs,
                              "fields": data, "colliders": colliders})
        scenes[path.name] = instances
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        print(path.name, len(instances), flush=True)
    counts = Counter(item["type"] for scene in scenes.values() for item in scene)
    dump(output, {"schema": 1, "scope": "All serialized level files; runtime-only prefabs require a separate audit.",
                  "types": types, "counts": dict(sorted(counts.items())), "scenes": scenes, "source_sha256": hashes})
    print("Scene component counts:", dict(sorted(counts.items())), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, args.decompiled_directory,
           Path(__file__).resolve().parents[1] / "Original/INARI/mechanism_catalog.json")
