"""Export wind Animator states, original sprite frames and material float/color curves."""

import argparse
import hashlib
import json
import zlib
from pathlib import Path

from import_inari import Importer, UnityPy, dump
from import_inari_arrow import save_pixels
from unity_scene_animation import animator_tracks, streamed_curves, target_paths

PROPERTIES = {
    "_Glow": "glow_amount",
    "_GlowGlobal": "glow_global",
    "_GlowColor": "glow_tint",
    "_ColorChangeNewCol": "color_change_new_color",
}


def material_tracks(clip):
    data = clip["m_MuscleClip"]["m_Clip"]["data"]
    assert data["m_DenseClip"]["m_CurveCount"] == 0
    curves = streamed_curves(clip)
    first_constant = (
        data["m_StreamedClip"]["curveCount"] + data["m_StreamedClip"]["discreteCurveCount"]
    )
    for index, value in enumerate(data["m_ConstantClip"]["data"]):
        curves[first_constant + index] = [[0.0, [0.0, 0.0, 0.0, value]]]
    bindings = clip["m_ClipBindingConstant"]["genericBindings"]
    assert len(curves) == len(bindings)
    names = {zlib.crc32(name.encode()) & 0x0FFFFFFF: name for name in PROPERTIES}
    result = []
    for index, binding in enumerate(bindings):
        assert binding["path"] == 0 and binding["typeID"] == 212
        if binding["isPPtrCurve"]:
            assert binding["customType"] == 23
            continue
        assert binding["customType"] == 22
        attribute = binding["attribute"]
        name = names[attribute & 0x0FFFFFFF]
        component = (attribute >> 28) - 4
        assert component in (0, 1, 2, 3, 4)
        result.append(
            {
                "property": name,
                "uniform": PROPERTIES[name],
                "component": -1 if component == 4 else component,
                "binding": attribute,
                "keys": curves[index],
            }
        )
    return result


def export(source, output):
    wind = json.loads((output / "wind_buff.json").read_text(encoding="utf8"))
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.sprites = json.loads((output / "sprites.json").read_text(encoding="utf8"))
    # Regenerate this export's own frames so repeated imports also verify source pixels.
    importer.sprites = {
        k: v for k, v in importer.sprites.items() if not v.get("path", "").startswith("WindBuff/")
    }
    importer.images, importer.materials = {}, {}
    importer.material_details, importer.texture_assets = {}, {}
    levels, controllers, files = {}, {}, set()
    for level, entries in wind["levels"].items():
        levels[level] = []
        if not entries:
            continue
        files.add(level)
        env = UnityPy.load(str(source / level))
        objects = {obj.path_id: obj for obj in env.objects}
        transforms = {
            o.path_id: o.read_typetree() for o in env.objects if o.type.name == "Transform"
        }
        gos = {o.path_id: o.read_typetree() for o in env.objects if o.type.name == "GameObject"}
        by_go = {t["m_GameObject"]["m_PathID"]: tid for tid, t in transforms.items()}
        for entry in entries:
            obj = objects[entry["animator_id"]]
            animator = obj.read()
            go = animator.m_GameObject.path_id
            controller = animator.m_Controller.read_typetree()
            name = controller["m_Name"]
            levels[level].append({"trigger_go": entry["go"], "visual_go": go, "controller": name})
            if name in controllers:
                continue
            files.add(animator.m_Controller.deref().assets_file.name)
            paths = target_paths(go, gos, transforms, by_go)
            machine = controller["m_Controller"]["m_StateMachineArray"][0]["data"]
            names = dict(controller["m_TOS"])
            states = []
            for index, item in enumerate(machine["m_StateConstantArray"]):
                state = item["data"]
                assert state["m_WriteDefaultValues"] and state["m_CycleOffset"] == 0
                tracks = animator_tracks(
                    importer, obj, paths, transforms, by_go, selected_state=index
                )
                assert len(tracks) == 1 and tracks[0]["kind"] == "sprite"
                track = tracks[0]
                leaf = state["m_BlendTreeConstantArray"][0]["data"]["m_NodeArray"][0]["data"]
                pointer = animator.m_Controller.read().m_AnimationClips[leaf["m_ClipID"]]
                files.add(pointer.deref().assets_file.name)
                clip = pointer.read_typetree()
                transitions = []
                for transition in state["m_TransitionConstantArray"]:
                    value = transition["data"]
                    assert value["m_InterruptionSource"] == 0 and value["m_HasFixedDuration"]
                    conditions = value["m_ConditionConstantArray"]
                    assert len(conditions) <= 1
                    if conditions:
                        assert conditions[0]["data"]["m_ConditionMode"] == 1
                    transitions.append(
                        {
                            "destination": value["m_DestinationState"],
                            "duration": value["m_TransitionDuration"],
                            "offset": value["m_TransitionOffset"],
                            "exit_time": value["m_ExitTime"] if value["m_HasExitTime"] else None,
                            "trigger": (
                                names[conditions[0]["data"]["m_EventID"]] if conditions else ""
                            ),
                        }
                    )
                states.append(
                    {
                        "name": names[state["m_NameID"]],
                        "clip": clip["m_Name"],
                        "length": track["length"],
                        "speed": track["speed"],
                        "loop": track["loop"],
                        "frames": track["frames"],
                        "material_tracks": material_tracks(clip),
                        "transitions": transitions,
                    }
                )
            controllers[name] = {"default": machine["m_DefaultState"], "states": states}
    directory = output / "WindBuff"
    directory.mkdir(parents=True, exist_ok=True)
    for key, image in sorted(importer.images.items()):
        info = save_pixels(image, directory, key + ".png")
        info["path"] = "WindBuff/" + info["path"]
        info["region"] = [0, 0, image.width, image.height]
        importer.sprites[key].update(info)
        files.add(key.rsplit("_", 1)[0] + ".assets")
    dump(output / "sprites.json", importer.sprites)
    dump(
        output / "wind_animation.json",
        {
            "levels": levels,
            "controllers": controllers,
            "new_frames": sorted(importer.images),
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                for name in sorted(files)
            },
        },
    )
    print(
        "Native wind controllers:", list(controllers), "new original frames:", len(importer.images)
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
