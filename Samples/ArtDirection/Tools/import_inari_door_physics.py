"""Export original door Rigidbody2D settings and its resolved collision layers."""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr
from import_inari_damage import number
from unity_scene_spatial import WorldTransforms


def export(source, decompiled, output):
    env = UnityPy.load(str(source / "globalgamemanagers"))
    names = next(o.read_typetree()["layers"] for o in env.objects if o.type.name == "TagManager")
    physics = next(o.read_typetree() for o in env.objects if o.type.name == "Physics2DSettings")
    door_mask = physics["m_LayerCollisionMatrix"][names.index("Door")]
    text = (decompiled / "InteractiveDoor.cs").read_text(encoding="utf8")
    result = {
        "gravity": physics["m_Gravity"],
        "launch_speed": number(text, r"velocity = vector \* ([\d.]+)f"),
        "angle_min": number(text, r"Random.Range\((-?[\d.]+)f"),
        "angle_max": number(text, r"Random.Range\(-?[\d.]+f, ([\d.]+)f"),
        "collision_layers": None,
        "physics_sha256": hashlib.sha256((source / "globalgamemanagers").read_bytes()).hexdigest(),
        "door_code_sha256": hashlib.sha256(text.encode("utf8")).hexdigest(),
        # Null native materials are not serialized. Keep this adapter assumption
        # explicit instead of presenting it as an extracted material value.
        "fallback_material": {"friction": 0.4, "bounce": 0.0, "verified_in_game": False},
    }
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    for path in sorted(output.glob("level*.json")):
        scene = json.loads(path.read_text(encoding="utf8"))
        doors = {door["go"]: door for door in scene.get("doors", [])}
        if not doors:
            continue
        env = UnityPy.load(str(source / path.stem))
        env.typetree_generator = generator
        transforms = {
            obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"
        }
        by_go = {data["m_GameObject"]["m_PathID"]: key for key, data in transforms.items()}
        world = WorldTransforms(transforms)
        count = 0
        for obj in env.objects:
            if obj.type.name != "MonoBehaviour":
                continue
            head = obj.parse_monobehaviour_head()
            if (
                head.m_GameObject.path_id not in doors
                or head.m_Script.read().m_ClassName != "InteractiveDoor"
            ):
                continue
            data = obj.read_typetree()
            door = doors[head.m_GameObject.path_id]
            pieces = {piece["go"]: piece for piece in door["pieces"]}
            for reference in data["interactiveDoorParticles"]:
                rigid = PPtr(**reference["rigidbody"], assetsfile=obj.assets_file).read_typetree()
                assert not rigid["m_Material"][
                    "m_PathID"
                ], "Import the authored physics material first"
                piece = pieces[reference["gameObject"]["m_PathID"]]
                piece["rigid_body"] = rigid
                piece["body_transform"] = world.sprite_plane(by_go[piece["go"]], 16.0)["transform"]
                mask = (door_mask | rigid["m_IncludeLayers"]["m_Bits"]) & ~rigid["m_ExcludeLayers"][
                    "m_Bits"
                ]
                layers = [name for index, name in enumerate(names) if mask & (1 << index)]
                if result["collision_layers"] is None:
                    result["collision_layers"] = layers
                assert (
                    layers == result["collision_layers"]
                ), "Door fragments need distinct collision masks"
                count += 1
        path.write_text(json.dumps(scene, separators=(",", ":")) + "\n", encoding="utf8")
        print(path.name, "rigid fragments", count)
    (output / "door_physics.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")


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
