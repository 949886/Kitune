"""Append only the weak-point branches enabled by the installed enemy controller."""

import argparse
import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump
from import_inari_damage import number
from unity_scene_animation import animator_tracks, target_paths
from unity_scene_spatial import WorldTransforms


def read(path):
    return json.loads(path.read_text(encoding="utf8"))


def export(source, decompiled, output):
    scene = read(output / "level15.json")
    actors = {actor["go"]: actor for actor in scene["enemies"]}
    env = UnityPy.load(str(source / "level15"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    objects = {obj.path_id: obj for obj in env.objects}
    gos = {
        key: obj.read_typetree() for key, obj in objects.items() if obj.type.name == "GameObject"
    }
    transforms = {
        key: obj.read_typetree() for key, obj in objects.items() if obj.type.name == "Transform"
    }
    by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}
    world = WorldTransforms(transforms)
    evidence_path = output / "weakpoints.json"
    evidence = read(evidence_path) if evidence_path.exists() else {"added_sprite_sha256": {}}
    evidence["actors"] = {}
    selected = set()

    def active_branch(root):
        result, pending = [], [root]
        while pending:
            go = pending.pop()
            result.append(go)
            for child in transforms[by_go[go]]["m_Children"]:
                child_go = transforms[child["m_PathID"]]["m_GameObject"]["m_PathID"]
                if gos[child_go]["m_IsActive"]:
                    pending.append(child_go)
        return result

    for actor in actors.values():
        obj = objects[actor["source_id"]]
        actor_source = obj.read_typetree()
        entity = PPtr(**actor_source["Entity"], assetsfile=obj.assets_file).read_typetree()
        outline_visuals = sorted(
            {
                PPtr(**reference, assetsfile=obj.assets_file).read_typetree()["m_GameObject"][
                    "m_PathID"
                ]
                for reference in actor_source["otherRenderers"]
                if reference["m_PathID"]
            }
        )
        actor["hit_visuals"] = sorted({actor["primary_visual"]} | set(outline_visuals))
        ref = entity["EnemyWeakPointComponent"]["_enemyWeakpointController"]
        controller = PPtr(**ref, assetsfile=obj.assets_file).read_typetree()
        stacks = [active_branch(ref["m_PathID"]) for ref in controller["weakPointStackObjects"]]
        range_go = controller["weakPointRange"]["m_PathID"]
        members = active_branch(range_go)
        pose = transforms[by_go[range_go]]
        assert pose["m_LocalScale"] == {"x": 1.0, "y": 1.0, "z": 1.0}
        collider = PPtr(
            **controller["weakPointRangeCollider"], assetsfile=obj.assets_file
        ).read_typetree()
        evidence["actors"][str(actor["go"])] = {
            "outline_visuals": outline_visuals,
            "stacks": stacks,
            "range_members": members,
            "range_transform": world.sprite_plane(by_go[range_go], 16.0)["transform"],
            "range_collider": collider,
        }
        selected.update(members)
        for group in stacks:
            selected.update(group)

    sprites = read(output / "sprites.json")
    provenance = read(output / "provenance.json")
    with tempfile.TemporaryDirectory(prefix="inari-weakpoints-") as temporary:
        staging = Path(temporary)
        importer = Importer(source, staging)
        importer.sprites = copy.deepcopy(sprites)
        importer.scene(15, selected)
        decoded = read(staging / "level15.json")
        fresh_actors = {actor["go"]: actor for actor in decoded["enemies"]}
        visible_ids = {item["go"] for item in decoded["sprites"]}
        existing_ids = {item["go"] for item in scene["sprites"]}
        for key, definition in evidence["actors"].items():
            tracks = []
            empty_clips = []
            for go in definition["range_members"]:
                for entry in gos[go]["m_Component"]:
                    obj = objects[entry["component"]["m_PathID"]]
                    if obj.type.name == "Animator" and obj.read().m_Enabled:
                        animation = animator_tracks(
                            importer,
                            obj,
                            target_paths(go, gos, transforms, by_go),
                            transforms,
                            by_go,
                        )
                        tracks.extend(animation)
                        if not animation:
                            for pointer in obj.read().m_Controller.read().m_AnimationClips:
                                clip = pointer.read_typetree()
                                assert not clip["m_ClipBindingConstant"][
                                    "genericBindings"
                                ], "An empty result must not hide unsupported range animation bindings"
                                empty_clips.append(
                                    {
                                        "go": go,
                                        "name": clip["m_Name"],
                                        "source_id": pointer.path_id,
                                        "source_file": pointer.deref().assets_file.name,
                                    }
                                )
            definition["animations"] = tracks
            definition["empty_range_clips"] = empty_clips
            definition["stacks"] = [
                [go for go in group if go in visible_ids] for group in definition["stacks"]
            ]
            definition["range_members"] = [
                go for go in definition["range_members"] if go in visible_ids
            ]
            actor = actors[int(key)]
            # A full decoder can discover unrelated dependencies that this
            # incremental update deliberately does not add to the scene.
            for field in ("visuals", "gfx_visuals"):
                retained = set(actor[field]) & existing_ids
                additions = set(fresh_actors[int(key)][field]) & selected
                actor[field] = sorted(retained | additions)
        existing = {item["go"] for item in scene["sprites"]}
        additions = [
            item
            for item in decoded["sprites"]
            if item["go"] in selected and item["go"] not in existing
        ]
        scene["sprites"].extend(additions)
        materials = read(output / "materials.json")
        for item in additions:
            materials.setdefault(item["material"], importer.material_details[item["material"]])
        if importer.images:
            importer.atlases(start_page=provenance["atlas_count"])
            fresh = read(staging / "provenance.json")
            for page in range(provenance["atlas_count"], fresh["atlas_count"]):
                shutil.copyfile(staging / f"atlas_{page}.png", output / f"atlas_{page}.png")
            provenance["atlas_count"] = fresh["atlas_count"]
            for key, pixels in importer.images.items():
                sprites[key] = importer.sprites[key]
                evidence["added_sprite_sha256"][key] = hashlib.sha256(pixels.tobytes()).hexdigest()
                filename = key.rsplit("_", 1)[0] + ".assets"
                provenance["source_files"][filename] = hashlib.sha256(
                    (source / filename).read_bytes()
                ).hexdigest()
        provenance["sprite_count"] = len(sprites)
        code = (decompiled / "EnemyWeakpointController.cs").read_text(encoding="utf8")
        evidence["scale_duration"] = number(code, r"DOScale\(scale, ([\d.]+)f")
        names = [
            "EnemyWeakpointController.cs",
            "EnemyWeakPointComponent.cs",
            "WeakPointComponent.cs",
            "Enemy.StateMachine/EnemyStateMachine.cs",
        ]
        evidence["source_sha256"] = {
            name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest() for name in names
        }
        for name in ["level15", "Managed/Assembly-CSharp.dll", "Managed/DOTween.dll"]:
            evidence["source_sha256"][name] = hashlib.sha256(
                (source / name).read_bytes()
            ).hexdigest()
        for name, value in [
            ("level15.json", scene),
            ("sprites.json", sprites),
            ("materials.json", materials),
            ("provenance.json", provenance),
            ("weakpoints.json", evidence),
        ]:
            dump(output / name, value)
        for page in {sprites[key]["atlas"] for key in evidence["added_sprite_sha256"]}:
            options = output / f"atlas_{page}.png.import"
            if options.exists():
                options.write_text(
                    options.read_text(encoding="utf8").replace(
                        "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                    ),
                    encoding="utf8",
                )
        print(
            "Added",
            len(importer.images),
            "original sprites and",
            len(additions),
            "weak-point renderers",
        )
        print(
            "Range animation kinds:",
            sorted(
                {
                    track["kind"]
                    for actor in evidence["actors"].values()
                    for track in actor["animations"]
                }
            ),
        )


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
