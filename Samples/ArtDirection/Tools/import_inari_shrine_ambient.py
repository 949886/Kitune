"""Extract the shrine's bound Timeline loops and Kurori conversation pose for the visual-study profile.

This exports an ambient pose and its bound camera, not the complete dialogue Timeline.
All frames, rates and renderer bindings come from the installed game's data.
"""

import argparse
import hashlib
import json
from pathlib import Path

from import_inari import Importer, PIXELS_PER_UNIT, TypeTreeGenerator, UnityPy, dump
from import_inari_arrow import save_pixels
from unity_shrine_pose import kurori_pose, player_pose, scene_poses
from unity_shrine_camera import conversation_camera


def sprite_loop(importer, track, clip, go, files):
    value = importer.pointer(track.assets_file, clip["m_Asset"]).deref()
    animation = value.read_typetree()["spriteAnimationData"]
    assert animation["Loop"] and animation["FrameRate"] > 0
    frames = []
    for index, pointer in enumerate(animation["Sprites"]):
        sprite = importer.pointer(value.assets_file, pointer)
        files.add(sprite.deref().assets_file.name)
        frames.append([index / animation["FrameRate"], importer.sprite(sprite)])
    return {
        "go": go,
        "kind": "sprite",
        "name": clip["m_DisplayName"],
        "clock": "timeline_loop",
        "frame_rate": animation["FrameRate"],
        "length": len(frames) / animation["FrameRate"],
        "speed": 1.0,
        "loop": True,
        "reset_on_loop": False,
        "frames": frames,
        "source_track": track.path_id,
        "source_clip": value.path_id,
        "source_start": clip["m_Start"],
        "source_duration": clip["m_Duration"],
    }


def export(source, output):
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    importer.sprites = {
        key: value
        for key, value in importer.sprites.items()
        if not value.get("path", "").startswith("ShrineAmbient/")
    }
    importer.images = {}
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "level25"))
    env.typetree_generator = generator
    files = {"level25"}
    tracks, poses, proofs = [], [], []
    objects = {obj.path_id: obj for obj in env.objects}
    scene = json.loads((output / "level25.json").read_text(encoding="utf8"))
    for director in env.objects:
        if director.type.name != "PlayableDirector":
            continue
        data = director.read_typetree()
        asset = importer.pointer(director.assets_file, data["m_PlayableAsset"]).deref()
        timeline = asset.read_typetree()
        if timeline["m_Name"] != "TIMLINE_CUTSCENE_INTRO_KURORI":
            continue
        files.add(asset.assets_file.name)
        for binding in data["m_SceneBindings"]:
            if not binding["key"]["m_PathID"] or not binding["value"]["m_PathID"]:
                continue
            track = importer.pointer(director.assets_file, binding["key"]).deref()
            tree = track.read_typetree()
            if (
                track.parse_monobehaviour_head().m_Script.read().m_ClassName
                != "SpriteAnimationTrack"
            ):
                continue
            for clip in tree["m_Clips"]:
                if clip["m_DisplayName"] != "BowIdle":
                    continue
                renderer = importer.pointer(director.assets_file, binding["value"]).read()
                tracks.append(
                    sprite_loop(importer, track, clip, renderer.m_GameObject.path_id, files)
                )
        track, clip, pose, proof = kurori_pose(
            importer, director, objects, scene, files, PIXELS_PER_UNIT
        )
        poses.append(pose)
        proofs.append(proof)
        tracks.append(sprite_loop(importer, track, clip, pose["go"], files))
        camera = conversation_camera(
            importer, director, objects, generator, proof["sample_time"], files, PIXELS_PER_UNIT
        )
        # The unbound sprite track is attached to the runtime player by the source
        # Timeline binding provider. Keep it separate from scene-renderer tracks.
        player_track = next(
            importer.pointer(director.assets_file, binding["key"]).deref()
            for binding in data["m_SceneBindings"]
            if binding["key"]["m_PathID"]
            and not binding["value"]["m_PathID"]
            and importer.pointer(director.assets_file, binding["key"])
            .deref()
            .parse_monobehaviour_head()
            .m_Script.read()
            .m_ClassName
            == "SpriteAnimationTrack"
        )
        player_clip = next(
            clip
            for clip in player_track.read_typetree()["m_Clips"]
            if clip["m_DisplayName"] == "BackIDLE"
            and clip["m_Start"] == proof["player_back_idle_start"]
        )
        player_idle = sprite_loop(importer, player_track, player_clip, None, files)
        player_idle["pose"] = player_pose(
            importer, director, proof["sample_time"], files, PIXELS_PER_UNIT
        )
        scenery, scenery_proofs = scene_poses(
            importer,
            director,
            objects,
            scene,
            proof["sample_time"],
            {pose["go"]},
            files,
            PIXELS_PER_UNIT,
        )
        poses.extend(scenery)
    assert len(tracks) == 6 and len({track["go"] for track in tracks}) == 6
    directory = output / "ShrineAmbient"
    directory.mkdir(parents=True, exist_ok=True)
    for key, image in sorted(importer.images.items()):
        info = save_pixels(image, directory, key + ".png")
        info["path"] = "ShrineAmbient/" + info["path"]
        info["region"] = [0, 0, image.width, image.height]
        importer.sprites[key].update(info)
    dump(output / "sprites.json", importer.sprites)
    dump(
        output / "shrine_ambient.json",
        {
            "source": "level25",
            "timeline": "TIMLINE_CUTSCENE_INTRO_KURORI",
            "excerpt": "BowIdle and Kurori conversation idle",
            "poses": poses,
            "pose_evidence": proofs,
            "scene_pose_evidence": scenery_proofs,
            "camera": camera,
            "player_idle": player_idle,
            "tracks": sorted(tracks, key=lambda track: track["go"]),
            "new_frames": sorted(importer.images),
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                for name in sorted(files)
            },
        },
    )
    print("Shrine ambient:", len(tracks), "bindings,", len(importer.images), "native frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / "Original/INARI"
    )
    args = parser.parse_args()
    export(args.data_directory, args.output)
