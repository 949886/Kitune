"""Read default visual animation states from INARI's shipped Unity data.

Animator streams and SimpleAnimator caches use different clocks. Keep their
timing metadata instead of baking either format into an arbitrary frame rate.
"""

from __future__ import annotations

import math
import struct
import zlib
from unity_scene_spatial import WorldTransforms


def streamed_curves(clip):
    stream = clip["m_MuscleClip"]["m_Clip"]["data"]["m_StreamedClip"]["data"]
    raw = struct.pack(f"<{len(stream)}I", *stream)
    stop = clip["m_MuscleClip"]["m_StopTime"]
    curves, offset = {}, 0

    while offset + 8 <= len(raw):
        time, count = struct.unpack_from("<fI", raw, offset)
        offset += 8
        for _ in range(count):
            index, *coefficients = struct.unpack_from("<I4f", raw, offset)
            offset += 20
            if not math.isfinite(time) or time > stop + 0.00001:
                continue

            # Unity's negative-time sentinel supplies the initial value.
            keys = curves.setdefault(index, {})
            keys[max(0.0, time)] = coefficients

    return {
        index: [[time, value] for time, value in sorted(keys.items())]
        for index, keys in curves.items()
    }


def binding_width(binding):
    if binding["typeID"] == 4:
        return 4 if binding["attribute"] == 2 else 3
    return 1


def target_paths(root_go, gos, transforms, by_go):
    paths = {0: root_go}

    def visit(tid, path):
        for child in transforms[tid]["m_Children"]:
            child_id = child["m_PathID"]
            child_go = transforms[child_id]["m_GameObject"]["m_PathID"]
            relative = "/".join(filter(None, [path, gos[child_go]["m_Name"]]))
            paths[zlib.crc32(relative.encode("utf8"))] = child_go
            visit(child_id, relative)

    visit(by_go[root_go], "")
    return paths


def animator_tracks(
    importer, obj, paths, transforms, by_go, selected_state=None, selected_clip=None
):
    animator = obj.read()
    controller = animator.m_Controller.read_typetree()
    if "m_Controller" not in controller:
        return []

    tracks = []
    machine_array = controller["m_Controller"]["m_StateMachineArray"]
    clip_pointers = animator.m_Controller.read().m_AnimationClips
    for layer_index, layer in enumerate(controller["m_Controller"]["m_LayerArray"]):
        if selected_state is not None and layer_index != 0:
            continue
        layer = layer["data"]
        if layer_index > 0 and layer["m_DefaultWeight"] == 0:
            continue
        machine = machine_array[layer["m_StateMachineIndex"]]["data"]
        if machine["m_DefaultState"] >= len(machine["m_StateConstantArray"]):
            continue
        state_index = machine["m_DefaultState"] if selected_state is None else selected_state
        state = machine["m_StateConstantArray"][state_index]["data"]
        nodes = [
            node["data"]
            for tree in state["m_BlendTreeConstantArray"]
            for node in tree["data"]["m_NodeArray"]
        ]
        leaves = [
            node
            for node in nodes
            if not node["m_ChildIndices"] and node["m_ClipID"] < len(clip_pointers)
        ]
        # A blend tree needs its parameter evaluation; do not pick an arbitrary leaf.
        if selected_clip is not None:
            leaves = [node for node in leaves if node["m_ClipID"] == selected_clip]
        if len(leaves) != 1:
            continue

        pointer = clip_pointers[leaves[0]["m_ClipID"]]
        clip = pointer.read_typetree()
        curves = streamed_curves(clip)
        mapping = clip["m_ClipBindingConstant"]["pptrCurveMapping"]
        source_file = pointer.deref().assets_file
        base = dict(
            source="Animator",
            clip=clip["m_Name"],
            controller=controller["m_Name"],
            length=clip["m_MuscleClip"]["m_StopTime"],
            frame_rate=clip["m_SampleRate"],
            speed=state["m_Speed"],
            loop=clip["m_MuscleClip"]["m_LoopTime"],
            reset_on_loop=False,
            write_defaults=state["m_WriteDefaultValues"],
        )
        bindings = clip["m_ClipBindingConstant"]["genericBindings"]
        unsupported = [
            binding
            for binding in bindings
            if not (
                (
                    binding["typeID"] == 212
                    and binding["isPPtrCurve"]
                    and binding["customType"] in (21, 23)
                )
                or (binding["typeID"] == 4 and binding["attribute"] in (1, 4))
                or (binding["typeID"] == 1 and binding["attribute"] == zlib.crc32(b"m_IsActive"))
            )
        ]
        if unsupported:
            # Preserve unported bindings as evidence. In particular a renderer
            # material slot must never be misdecoded as a Sprite reference.
            base["unsupported_bindings"] = unsupported
        index = 0
        for binding in bindings:
            target = paths.get(binding["path"])
            if target is not None:
                if (
                    binding["isPPtrCurve"]
                    and binding["typeID"] == 212
                    and binding["customType"] in (21, 23)
                ):
                    kind = "sprite" if binding["customType"] == 23 else "material"
                    frames = []
                    for time, coeff in curves.get(index, []):
                        mapped_index = round(coeff[3])
                        if 0 <= mapped_index < len(mapping) and time < base["length"]:
                            reference = importer.pointer(source_file, mapping[mapped_index])
                            if kind == "sprite":
                                value = importer.sprite(reference)
                            else:
                                assert reference and reference.deref().type.name == "Material"
                                importer.material(reference)
                                value = reference.read().m_Name
                            frames.append([time, value])
                    if frames:
                        tracks.append(dict(base, go=target, kind=kind, frames=frames))

                elif binding["typeID"] == 1 and binding["attribute"] == zlib.crc32(b"m_IsActive"):
                    keys = curves.get(index, [])
                    if keys:
                        tracks.append(dict(base, go=target, kind="active", keys=keys))

                elif binding["typeID"] == 4 and binding["attribute"] == 1:
                    transform = transforms[by_go[target]]
                    parent = transform["m_Father"]["m_PathID"]
                    plane = WorldTransforms(transforms).sprite_plane(parent, 16.0)
                    assert plane["parallel"], "Animated translation needs a parallel source parent"
                    initial = transform["m_LocalPosition"]
                    tracks.append(
                        dict(
                            base,
                            go=target,
                            kind="position",
                            axes=[curves.get(index + axis, []) for axis in range(3)],
                            initial=[initial[axis] for axis in ("x", "y", "z")],
                            parent_basis=plane["transform"][:4],
                        )
                    )

                elif binding["typeID"] == 4 and binding["attribute"] == 4:
                    # This build's fan animation stores XYZ Euler angles as three curves.
                    keys = curves.get(index + 2, [])
                    q = transforms[by_go[target]]["m_LocalRotation"]
                    initial_angle = math.degrees(2 * math.atan2(q["z"], q["w"]))
                    if keys:
                        tracks.append(
                            dict(
                                base,
                                go=target,
                                kind="rotation",
                                keys=keys,
                                initial_angle=initial_angle,
                            )
                        )

            index += binding_width(binding)

    return tracks


def simple_tracks(importer, obj, data):
    state = next(
        (state for state in data["cachedStates"] if state["stateName"] == data["defaultStateName"]),
        None,
    )
    if not state or not state["sprites"]:
        return []

    frames = []
    for index, pointer in enumerate(state["sprites"]):
        sprite = importer.sprite(importer.pointer(obj.assets_file, pointer))
        frames.append([index / state["frameRate"], sprite])

    return [
        dict(
            source="SimpleAnimator",
            clip=state["stateName"],
            go=data["m_GameObject"]["m_PathID"],
            kind="sprite",
            frames=frames,
            length=state["length"],
            speed=data["animationSpeed"],
            loop=bool(state["isLoop"]),
            reset_on_loop=True,
            frame_rate=state["frameRate"],
        )
    ]


def collect_tracks(importer, objects, gos, transforms, by_go, active, visual_gos):
    tracks = []
    for obj in objects:
        if obj.type.name == "Animator":
            animator = obj.read()
            go = animator.m_GameObject.path_id
            if not animator.m_Enabled or not animator.m_Controller or not active(by_go[go]):
                continue
            paths = target_paths(go, gos, transforms, by_go)
            tracks.extend(animator_tracks(importer, obj, paths, transforms, by_go))

        elif obj.type.name == "MonoBehaviour":
            head = obj.parse_monobehaviour_head()
            if head.m_Script.read().m_ClassName != "SimpleAnimator":
                continue
            data = obj.read_typetree()
            go = data["m_GameObject"]["m_PathID"]
            if data["m_Enabled"] and active(by_go[go]):
                tracks.extend(simple_tracks(importer, obj, data))

    return [track for track in tracks if track["go"] in visual_gos]
