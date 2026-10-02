"""Read a source conversation pose without replaying or inventing its choreography."""

import copy
import zlib

from unity_scene_animation import binding_width, streamed_curves
from unity_scene_spatial import WorldTransforms


def sample(keys, time):
    key = keys[0]
    for candidate in keys:
        if candidate[0] > time:
            break
        key = candidate
    delta = max(0.0, time - key[0])
    a, b, c, d = key[1]
    return ((a * delta + b) * delta + c) * delta + d


def clip_channels(clip):
    data = clip["m_MuscleClip"]["m_Clip"]["data"]
    assert data["m_DenseClip"]["m_CurveCount"] == 0
    channels = streamed_curves(clip)
    offset = data["m_StreamedClip"]["curveCount"] + data["m_StreamedClip"]["discreteCurveCount"]
    for index, value in enumerate(data["m_ConstantClip"]["data"]):
        channels[offset + index] = [[0.0, [0.0, 0.0, 0.0, value]]]
    return channels


def selected_clip(track, time):
    active = [c for c in track["m_Clips"] if c["m_Start"] <= time < c["m_Start"] + c["m_Duration"]]
    if active:
        # The selected pose is outside all position crossfades.
        assert len(active) == 1
        return active[0]
    previous = [c for c in track["m_Clips"] if c["m_Start"] + c["m_Duration"] <= time]
    if not previous:
        clip = min(track["m_Clips"], key=lambda c: c["m_Start"])
        assert clip["m_PreExtrapolationMode"] == 1
        assert clip["m_Start"] - clip["m_PreExtrapolationTime"] <= time < clip["m_Start"]
        return clip
    clip = max(previous, key=lambda c: c["m_Start"] + c["m_Duration"])
    assert clip["m_PostExtrapolationMode"] == 1  # Timeline Hold, not a guessed default.
    return clip


def kurori_pose(importer, director, objects, scene, files, pixels_per_unit):
    bindings = []
    for binding in director.read_typetree()["m_SceneBindings"]:
        if not binding["key"]["m_PathID"]:
            continue
        obj = importer.pointer(director.assets_file, binding["key"]).deref()
        name = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
        if name not in ("SpriteAnimationTrack", "AnimationTrack"):
            continue
        target = binding["value"]["m_PathID"]
        go = objects[target].read_typetree()["m_GameObject"]["m_PathID"] if target else None
        bindings.append((obj, name, go, obj.read_typetree()))
    subject = next(
        o for o in objects.values() if o.type.name == "GameObject" and o.peek_name() == "Kurori"
    )
    sprite_track = next(
        b for b in bindings if b[1] == "SpriteAnimationTrack" and b[2] == subject.path_id
    )
    player_back = sorted(
        [
            c
            for _, kind, go, tree in bindings
            if kind == "SpriteAnimationTrack" and go is None
            for c in tree["m_Clips"]
            if c["m_DisplayName"] == "BackIDLE"
        ],
        key=lambda c: c["m_Start"],
    )[0]
    start, end = player_back["m_Start"], player_back["m_Start"] + player_back["m_Duration"]
    idle = max(
        [
            c
            for c in sprite_track[3]["m_Clips"]
            if c["m_DisplayName"] == "IDLE"
            and c["m_Start"] < end
            and c["m_Start"] + c["m_Duration"] > start
        ],
        key=lambda c: c["m_Start"],
    )
    time = (max(start, idle["m_Start"]) + min(end, idle["m_Start"] + idle["m_Duration"])) / 2
    transforms = {
        o.path_id: o.read_typetree() for o in objects.values() if o.type.name == "Transform"
    }
    transform_id = next(
        tid for tid, t in transforms.items() if t["m_GameObject"]["m_PathID"] == subject.path_id
    )
    transform = copy.deepcopy(transforms[transform_id])
    source = next(item for item in scene["sprites"] if item["go"] == subject.path_id)
    color, flip, order = list(source["color"]), list(source["flip"]), source["sort"][1]
    evidence = []
    for obj, kind, go, tree in bindings:
        if kind != "AnimationTrack" or go != subject.path_id:
            continue
        clip = selected_clip(tree, time)
        asset = importer.pointer(obj.assets_file, clip["m_Asset"]).deref()
        data = asset.read_typetree()
        pointer = importer.pointer(asset.assets_file, data["m_Clip"])
        native = pointer.read_typetree()
        files.update(
            [obj.assets_file.name, asset.assets_file.name, pointer.deref().assets_file.name]
        )
        assert [tree["m_Position"][axis] for axis in "xyz"] == [0, 0, 0]
        assert [data["m_Rotation"][axis] for axis in "xyzw"] == [0, 0, 0, 1]
        assert not data["m_RemoveStartOffset"]
        local = max(
            0,
            min(
                (time - clip["m_Start"]) * clip["m_TimeScale"] + clip["m_ClipIn"],
                native["m_MuscleClip"]["m_StopTime"],
            ),
        )
        channels, index, values = clip_channels(native), 0, {}
        for binding in native["m_ClipBindingConstant"]["genericBindings"]:
            assert binding["path"] == 0 and not binding["isPPtrCurve"]
            width = binding_width(binding)
            value = [sample(channels[index + axis], local) for axis in range(width)]
            index += width
            if binding["typeID"] == 4 and binding["attribute"] == 1:
                assert value == [
                    0,
                    0,
                    0,
                ], "This excerpt uses a constant root position plus its original clip offset"
                transform["m_LocalPosition"] = dict(data["m_Position"])
                values["position"] = transform["m_LocalPosition"]
                continue
            assert binding["typeID"] == 212 and width == 1
            names = ["m_Color." + channel for channel in "rgba"] + ["m_FlipX", "m_SortingOrder"]
            name = next(name for name in names if zlib.crc32(name.encode()) == binding["attribute"])
            values[name] = value[0]
            if name.startswith("m_Color."):
                color["rgba".index(name[-1])] = value[0]
            elif name == "m_FlipX":
                flip[0] = value[0] > 0.5
            else:
                assert binding["customType"] == 26
                order = round(value[0])
        evidence.append(
            {
                "track": obj.path_id,
                "asset": asset.path_id,
                "clip": pointer.path_id,
                "start": clip["m_Start"],
                "duration": clip["m_Duration"],
                "values": values,
            }
        )
    transforms[transform_id] = transform
    spatial = WorldTransforms(transforms).sprite_plane(transform_id, pixels_per_unit)
    assert spatial["parallel"]
    pose = {
        "go": subject.path_id,
        "transform": spatial["transform"],
        "spatial": spatial,
        "color": color,
        "flip": flip,
        "sort": [source["sort"][0], order],
    }
    proof = {
        "sample_time": time,
        "player_back_idle_start": start,
        "sprite_track": sprite_track[0].path_id,
        "sprite_clip": idle["m_Asset"]["m_PathID"],
        "bindings": evidence,
    }
    return sprite_track[0], idle, pose, proof


def player_pose(importer, director, time, files, units):
    """Sample the dynamically bound player root, including its authored facing."""
    candidates = []
    for binding in director.read_typetree()["m_SceneBindings"]:
        if not binding["key"]["m_PathID"] or binding["value"]["m_PathID"]:
            continue
        obj = importer.pointer(director.assets_file, binding["key"]).deref()
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "AnimationTrack":
            candidates.append(obj)
    assert len(candidates) == 1
    track = candidates[0]
    tree = track.read_typetree()
    clip = selected_clip(tree, time)
    asset = importer.pointer(track.assets_file, clip["m_Asset"]).deref()
    data = asset.read_typetree()
    native = importer.pointer(asset.assets_file, data["m_Clip"]).deref()
    source = native.read_typetree()
    channels = clip_channels(source)
    local = min(
        max(0, (time - clip["m_Start"]) * clip["m_TimeScale"] + clip["m_ClipIn"]),
        source["m_MuscleClip"]["m_StopTime"],
    )
    bindings = source["m_ClipBindingConstant"]["genericBindings"]
    assert [(b["path"], b["typeID"], b["attribute"]) for b in bindings] == [(0, 4, 1), (0, 4, 3)]
    assert [sample(channels[i], local) for i in range(3)] == [0, 0, 0]
    assert [tree["m_Position"][a] for a in "xyz"] == [0, 0, 0]
    assert [data["m_Rotation"][a] for a in "xyzw"] == [0, 0, 0, 1]
    assert not data["m_RemoveStartOffset"]
    scale = [sample(channels[i], local) for i in range(3, 6)]
    assert abs(scale[0]) == 1 and scale[1:] == [1, 1]
    position = data["m_Position"]
    assert position["z"] == 0
    files.update([track.assets_file.name, asset.assets_file.name, native.assets_file.name])
    return {
        "root_position": [position["x"] * units, -position["y"] * units],
        "facing": scale[0],
        "sample_time": time,
        "track": track.path_id,
        "asset": asset.path_id,
        "clip": native.path_id,
        "start": clip["m_Start"],
        "duration": clip["m_Duration"],
    }


def scene_poses(importer, director, objects, scene, time, excluded, files, units):
    """Recover bound sprite colors and constant root offsets at this excerpt."""
    sprites = {item["go"]: item for item in scene["sprites"]}
    transforms = {
        o.path_id: o.read_typetree() for o in objects.values() if o.type.name == "Transform"
    }
    by_go = {t["m_GameObject"]["m_PathID"]: tid for tid, t in transforms.items()}
    poses, evidence = [], []
    color_names = {
        zlib.crc32(("m_Color." + name).encode()): index for index, name in enumerate("rgba")
    }
    for binding in director.read_typetree()["m_SceneBindings"]:
        if not binding["key"]["m_PathID"] or not binding["value"]["m_PathID"]:
            continue
        track = importer.pointer(director.assets_file, binding["key"]).deref()
        if track.parse_monobehaviour_head().m_Script.read().m_ClassName != "AnimationTrack":
            continue
        go = objects[binding["value"]["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"]
        if go not in sprites or go in excluded:
            continue
        tree = track.read_typetree()
        clip = selected_clip(tree, time)
        asset = importer.pointer(track.assets_file, clip["m_Asset"]).deref()
        data = asset.read_typetree()
        native = importer.pointer(asset.assets_file, data["m_Clip"]).deref()
        source = native.read_typetree()
        # Hold before the clip starts samples ClipIn, rather than a negative time.
        local = min(
            max(0, time - clip["m_Start"]) * clip["m_TimeScale"] + clip["m_ClipIn"],
            source["m_MuscleClip"]["m_StopTime"],
        )
        channels, index = clip_channels(source), 0
        pose = {"go": go, "color": list(sprites[go]["color"])}
        for curve in source["m_ClipBindingConstant"]["genericBindings"]:
            assert curve["path"] == 0 and not curve["isPPtrCurve"]
            width = binding_width(curve)
            values = [sample(channels[index + axis], local) for axis in range(width)]
            index += width
            if curve["typeID"] == 212:
                assert width == 1 and curve["attribute"] in color_names
                pose["color"][color_names[curve["attribute"]]] = values[0]
                continue
            assert curve["typeID"] == 4 and curve["attribute"] == 1 and values == [0, 0, 0]
            assert [tree["m_Position"][a] for a in "xyz"] == [0, 0, 0]
            assert [data["m_Rotation"][a] for a in "xyzw"] == [0, 0, 0, 1]
            assert not data["m_RemoveStartOffset"]
            tid = by_go[go]
            transform = copy.deepcopy(transforms[tid])
            transform["m_LocalPosition"] = dict(data["m_Position"])
            sampled = dict(transforms)
            sampled[tid] = transform
            pose["spatial"] = WorldTransforms(sampled).sprite_plane(tid, units)
            pose["transform"] = pose["spatial"]["transform"]
        poses.append(pose)
        evidence.append(
            {
                "go": go,
                "track": track.path_id,
                "asset": asset.path_id,
                "clip": native.path_id,
                "sample_time": time,
                "clip_time": local,
                "start": clip["m_Start"],
                "duration": clip["m_Duration"],
                "pre_hold": time < clip["m_Start"],
            }
        )
        files.update([track.assets_file.name, asset.assets_file.name, native.assets_file.name])
    return poses, evidence
