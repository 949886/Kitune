"""Export a source wind station, its Animator and optional host buff component."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
from import_inari import UnityPy, dump
from portable_device_assets import export_artwork, copy_if_changed


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    folder = package / "Assets/WindStation"
    folder.mkdir(parents=True, exist_ok=True)
    profile_file = root / "Samples/ArtDirection/Profiles/portable_wind.json"
    profile = json.loads(profile_file.read_text(encoding="utf8"))
    read = lambda name: json.loads((original / name).read_text(encoding="utf8"))
    rules, animation, controls = (
        read("wind_buff.json"),
        read("wind_animation.json"),
        read("controls.json"),
    )
    level = profile["scene"]
    record = copy.deepcopy(rules["levels"][level][profile["trigger_index"]])
    binding = next(
        e for e in animation["levels"][level] if e["trigger_go"] == record["go"]
    )
    controller = copy.deepcopy(animation["controllers"][binding["controller"]])
    env = UnityPy.load(str(source / level))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
    poses = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "Transform"
    }
    gos = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"
    }
    by_go = {v["m_GameObject"]["m_PathID"]: i for i, v in poses.items()}
    children, components = [], {}
    queue = [by_go[record["go"]]]
    while queue:
        pose = poses[queue.pop()]
        go = pose["m_GameObject"]["m_PathID"]
        children.append(go)
        components[go] = [
            objects[c["component"]["m_PathID"]].type.name
            for c in gos[go]["m_Component"]
        ]
        assert (
            "ParticleSystem" not in components[go]
        ), "New source child effect needs explicit export"
        queue.extend(c["m_PathID"] for c in pose["m_Children"])
    scene = read(level + ".json")
    visuals = [copy.deepcopy(v) for v in scene["sprites"] if v.get("go") in children]
    assert any(v["go"] == binding["visual_go"] for v in visuals)
    assert all(
        v["mode"] == 0 for v in visuals
    ), "New source slicing needs explicit export"
    origin = record["transform"][4:].copy()
    record["transform"][4:] = [0, 0]
    keys = {v["sprite"] for v in visuals if v["sprite"]}
    for state in controller["states"]:
        keys.update(frame[1] for frame in state["frames"] if frame[1])
    sprite_info = export_artwork(
        original,
        package,
        folder,
        read("sprites.json"),
        read("materials.json"),
        visuals,
        keys,
        origin,
    )
    audio = read("Audio/wind_events.json")
    for files in audio["groups"].values():
        for name in files:
            copy_if_changed(original / "Audio" / name, folder / name)
    dump(
        folder / "device.json",
        dict(
            record=record,
            sprites=visuals,
            sprite_info=sprite_info,
            audio=audio["groups"],
            controller=controller,
            animated_visual=binding["visual_go"],
            source_scene=level,
            source_origin=origin,
            source_components=components,
            source_sha256={
                level: hashlib.sha256((source / level).read_bytes()).hexdigest(),
                "profile": hashlib.sha256(profile_file.read_bytes()).hexdigest(),
            },
            input_sha256={
                name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                for name in [
                    level + ".json",
                    "sprites.json",
                    "materials.json",
                    "wind_buff.json",
                    "wind_animation.json",
                    "controls.json",
                    "Audio/wind_events.json",
                ]
            },
        ),
    )
    destination = package / "Devices/WindStation"
    destination.mkdir(parents=True, exist_ok=True)
    station = [
        f'trigger_size = Vector2({record["size"][0]}, {record["size"][1]})',
        f'trigger_offset = Vector2({record["offset"][0]}, {record["offset"][1]})',
        f'cooldown_seconds = {record["cooldown"]}',
        f'stamina_amount = {record["stamina"]}',
        f'story_heal_amount = {rules["story_heal"]}',
    ]
    speeds = [
        v * controls["pixels_per_unit"] for v in controls["combat"]["WindBuffSpeeds"]
    ]
    durations = controls["combat"]["WindBuffDurations"]
    buff = [
        "extra_speed_pixels = PackedFloat32Array(" + ", ".join(map(str, speeds)) + ")",
        "durations = PackedFloat32Array(" + ", ".join(map(str, durations)) + ")",
    ]
    for name, values in [("WindStationSettings", station), ("WindBuffSettings", buff)]:
        (destination / (name + ".tres")).write_text(
            '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Script" path="{name}.gd" id="1"]\n\n'
            '[resource]\nscript = ExtResource("1")\n' + "\n".join(values) + "\n",
            encoding="utf8",
            newline="\n",
        )
    print(
        "WindStation:",
        len(visuals),
        "visuals,",
        len(keys),
        "frames,",
        sum(map(len, audio["groups"].values())),
        "sounds",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    export(parser.parse_args().source)
