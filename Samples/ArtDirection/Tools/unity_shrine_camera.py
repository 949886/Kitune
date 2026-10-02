"""Resolve the original conversation shot at the exported Kurori pose time."""

import copy
import zlib

from unity_scene_spatial import WorldTransforms, read_virtual_camera
from unity_shrine_pose import clip_channels, sample, selected_clip


def conversation_camera(importer, director, objects, generator, time, files, units):
    data = director.read_typetree()
    tracks = []
    for binding in data["m_SceneBindings"]:
        if not binding["key"]["m_PathID"]:
            continue
        obj = importer.pointer(director.assets_file, binding["key"]).deref()
        kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
        if kind not in ("CinemachineTrack", "AnimationTrack"):
            continue
        target = binding["value"]["m_PathID"]
        go = objects[target].read_typetree()["m_GameObject"]["m_PathID"] if target else None
        tracks.append((obj, kind, go, obj.read_typetree()))

    track = next(t for t in tracks if t[1] == "CinemachineTrack")
    shot = selected_clip(track[3], time)
    shot_obj = importer.pointer(track[0].assets_file, shot["m_Asset"]).deref()
    exposed = shot_obj.read_typetree()["VirtualCamera"]["exposedName"]["id"]
    references = dict(data["m_ExposedReferences"]["m_References"])
    camera_obj = importer.pointer(director.assets_file, references[exposed]).deref()
    camera = read_virtual_camera(camera_obj, generator)
    owner = objects[camera["m_ComponentOwner"]["m_PathID"]].read_typetree()
    owner_go = owner["m_GameObject"]["m_PathID"]
    components = {}
    for obj in objects.values():
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if head.m_GameObject.path_id == owner_go:
            components[head.m_Script.read().m_ClassName] = obj.read_typetree()
    framing = components["CinemachineFramingTransposer"]
    noise = components["CinemachineBasicMultiChannelPerlin"]
    transforms = {
        o.path_id: o.read_typetree() for o in objects.values() if o.type.name == "Transform"
    }
    follow_id = camera["m_Follow"]["m_PathID"]
    follow = copy.deepcopy(transforms[follow_id])
    follow_go = follow["m_GameObject"]["m_PathID"]
    camera_go = camera["m_GameObject"]["m_PathID"]
    evidence = []
    for obj, kind, go, tree in tracks:
        if kind != "AnimationTrack" or go not in (follow_go, camera_go):
            continue
        clip = selected_clip(tree, time)
        asset = importer.pointer(obj.assets_file, clip["m_Asset"]).deref()
        value = asset.read_typetree()
        native_obj = importer.pointer(asset.assets_file, value["m_Clip"]).deref()
        native = native_obj.read_typetree()
        files.update([obj.assets_file.name, asset.assets_file.name, native_obj.assets_file.name])
        local = min(
            max(0, (time - clip["m_Start"]) * clip["m_TimeScale"] + clip["m_ClipIn"]),
            native["m_MuscleClip"]["m_StopTime"],
        )
        channels = clip_channels(native)
        bindings = native["m_ClipBindingConstant"]["genericBindings"]
        values = {}
        if go == follow_go:
            assert len(bindings) == 1
            binding = bindings[0]
            assert binding["path"] == 0 and binding["typeID"] == 4 and binding["attribute"] == 1
            assert [sample(channels[i], local) for i in range(3)] == [0, 0, 0]
            assert [tree["m_Position"][a] for a in "xyz"] == [0, 0, 0]
            assert [value["m_Rotation"][a] for a in "xyzw"] == [0, 0, 0, 1]
            assert not value["m_RemoveStartOffset"]
            follow["m_LocalPosition"] = dict(value["m_Position"])
            values["position"] = follow["m_LocalPosition"]
        else:
            # This held clip animates Perlin amplitude/frequency, not follow damping.
            child_name = objects[owner_go].peek_name()
            for index, binding in enumerate(bindings):
                assert binding["path"] == zlib.crc32(child_name.encode())
                assert binding["typeID"] == 114 and not binding["isPPtrCurve"]
                name = next(
                    n
                    for n in ("m_AmplitudeGain", "m_FrequencyGain")
                    if zlib.crc32(n.encode()) == binding["attribute"]
                )
                noise[name] = sample(channels[index], local)
                values[name] = noise[name]
        evidence.append(
            {
                "track": obj.path_id,
                "asset": asset.path_id,
                "clip": native_obj.path_id,
                "start": clip["m_Start"],
                "duration": clip["m_Duration"],
                "values": values,
            }
        )
    assert len(evidence) == 2
    assert noise["m_AmplitudeGain"] == noise["m_FrequencyGain"] == 0
    transforms[follow_id] = follow
    world = WorldTransforms(transforms).matrix(follow_id)
    assert world[2][3] == 0
    files.update(
        [track[0].assets_file.name, shot_obj.assets_file.name, camera_obj.assets_file.name]
    )
    return {
        "source": "level25",
        "virtual_camera": camera_obj.path_id,
        "lens": camera["m_Lens"],
        "distance": framing["m_CameraDistance"],
        "tracked_offset": framing["m_TrackedObjectOffset"],
        "screen_position": [framing["m_ScreenX"], framing["m_ScreenY"]],
        "damping": [framing["m_XDamping"], framing["m_YDamping"], framing["m_ZDamping"]],
        "framing": {
            k: v
            for k, v in framing.items()
            if k not in ("m_GameObject", "m_Enabled", "m_Script", "m_Name")
        },
        "follow": {
            "transform": follow_id,
            "game_object": objects[follow_go].peek_name(),
            "fixed_position": [world[0][3] * units, -world[1][3] * units],
        },
        "excerpt": {
            "sample_time": time,
            "shot": shot_obj.path_id,
            "start": shot["m_Start"],
            "duration": shot["m_Duration"],
            "bindings": evidence,
        },
    }
