"""Localize a source cabin, its station effects and the actual mid-route portal."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
from import_inari import UnityPy, PPtr, Importer, dump
from portable_device_assets import (
    collect_visuals,
    export_artwork,
    source_slicing,
    copy_if_changed,
)


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    folder = package / "Assets/Elevator"
    folder.mkdir(parents=True, exist_ok=True)
    profile_file = root / "Samples/ArtDirection/Profiles/portable_elevator.json"
    profile = json.loads(profile_file.read_text(encoding="utf8"))
    read = lambda name: json.loads((original / name).read_text(encoding="utf8"))
    machinery = read("machinery.json")
    level = profile["scene"]
    scene = machinery["levels"][level]
    elevator = copy.deepcopy(scene["elevators"][profile["elevator_index"]])
    assert len(elevator["targets"]) == 1
    platform = copy.deepcopy(
        next(p for p in scene["platforms"] if str(p["id"]) == elevator["targets"][0])
    )
    portal = copy.deepcopy(scene["scene_moves"][profile["scene_exit_index"]])
    assert not portal["fields"]["maintainInputOnTransition"]
    origin = platform["transform"][4:].copy()
    controllers = [
        elevator["button_animation"],
        elevator["door_animation"],
        platform["start_animation"],
        platform["end_animation"],
    ]
    ids = set(platform["children"] + elevator["children"])
    for controller in controllers:
        ids.update(controller.get("children", []))
    source_scene = read(level + ".json")
    visuals = collect_visuals(source_scene, ids)
    tracks = [t for t in source_scene["animations"] if t.get("go") in ids]
    keys = {v["sprite"] for v in visuals if v["sprite"]}
    track_sets = [tracks]
    for controller in controllers:
        track_sets.extend(s["tracks"] for s in controller.get("states", []))
    for track_set in track_sets:
        for track in track_set:
            if track["kind"] == "sprite":
                keys.update(f[1] for f in track["frames"] if f[1])
    env = UnityPy.load(str(source / level))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
    gos = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"
    }
    sprites, materials = read("sprites.json"), read("materials.json")
    slicing = source_slicing(objects, gos, visuals, sprites)
    # Start() replaces the button's renderer material with this referenced
    # outline material. Preserve that assignment, not only the editor material.
    source_object = objects[int(elevator["go"])]
    pointer = PPtr(
        **elevator["fields"]["defaultMaterial"], assetsfile=source_object.assets_file
    )
    material_object = pointer.deref()
    raw = material_object.read_typetree()
    importer = Importer(source, root / "tmp/art-direction/elevator-material-export")
    importer.material(pointer)
    material = copy.deepcopy(importer.material_details[raw["m_Name"]])
    floats, colors = dict(raw["m_SavedProperties"]["m_Floats"]), dict(
        raw["m_SavedProperties"]["m_Colors"]
    )
    material["base_outline"] = dict(
        color=[colors["_OutlineColor"][k] for k in "rgba"],
        alpha=floats["_OutlineAlpha"],
        glow=floats["_OutlineGlow"],
        pixel_width=floats["_OutlinePixelWidth"],
        pixel_perfect="OUTBASEPIXELPERF_ON" in raw["m_ValidKeywords"],
        width=floats["_OutlineWidth"],
    )
    materials["portable/elevator_button"] = material
    outline_ids = [
        objects[p["m_PathID"]].read_typetree()["m_GameObject"]["m_PathID"]
        for p in elevator["fields"]["objects"]
    ]
    for visual in visuals:
        if visual.get("go") in outline_ids:
            visual["material"] = "portable/elevator_button"
    sprite_info = export_artwork(
        original, package, folder, sprites, materials, visuals, keys, origin, slicing
    )
    for shape in (
        [platform, elevator["trigger"], portal["trigger"]]
        + elevator["doors"]
        + platform["child_colliders"]
    ):
        shape["transform"][4] -= origin[0]
        shape["transform"][5] -= origin[1]
    assert all(
        c["kind"] == "BoxCollider2D" and not c["hazard"] and not c["one_way"]
        for c in platform["child_colliders"]
    )
    # Particle extraction keeps the hierarchy, subtracting the same device origin.
    platform["animation"] = {"children": sorted(ids), "states": []}
    platform["particle_origin_world_pixels"] = origin
    audio = read("Audio/elevator_events.json")
    for files in audio["groups"].values():
        for name in files:
            copy_if_changed(original / "Audio" / name, folder / name)
    tween = read("kunai_fade.json")
    assert tween["ease"] == "OutQuad" and tween["dotween_settings_resource"] is None
    dump(
        folder / "device.json",
        dict(
            record=platform,
            elevator=elevator,
            scene_exit=portal,
            sprites=visuals,
            sprite_info=sprite_info,
            default_tracks=tracks,
            audio=audio["groups"],
            audio_loop_frames={
                name: r["timeline_loop_frames"]
                for name, r in audio["renders"].items()
                if not r["one_shot"]
            },
            gravity=read("Particles/effects.json")["gravity_2d"],
            source_scene=level,
            source_origin=origin,
            outline_ids=outline_ids,
            outline_ease=tween["ease"],
            rules=machinery["elevator_rules"],
            input_sha256={
                name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                for name in [
                    "machinery.json",
                    level + ".json",
                    "sprites.json",
                    "materials.json",
                    "kunai_fade.json",
                    "Audio/elevator_events.json",
                    "Particles/effects.json",
                ]
            },
            source_sha256={
                level: hashlib.sha256((source / level).read_bytes()).hexdigest(),
                material_object.assets_file.name: hashlib.sha256(
                    (source / material_object.assets_file.name).read_bytes()
                ).hexdigest(),
                "profile": hashlib.sha256(profile_file.read_bytes()).hexdigest(),
            },
        ),
    )
    fields = platform["fields"]
    values = [
        f'travel_offset = Vector2({platform["waypoints"][1][0]}, {platform["waypoints"][1][1]})',
        f'speed_pixels_per_second = {fields["Speed"] * 16}',
        f'wait_seconds = {fields["WaitTime"]}',
        f'ease_amount = {fields["EaseAmount"]}',
        f'door_release_seconds = {machinery["elevator_rules"]["door_release_delay"]}',
        f'outline_fade_seconds = {elevator["fields"]["alphaTime"]}',
        f'destination_key = "{Path(portal["destination"]).stem}"',
        f'scene_exit_offset = Vector2({portal["trigger"]["transform"][4]}, {portal["trigger"]["transform"][5]})',
        f'scene_exit_size = Vector2({portal["trigger"]["size"][0]}, {portal["trigger"]["size"][1]})',
    ]
    destination = package / "Devices/Elevator"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "ElevatorSettings.tres").write_text(
        '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="ElevatorSettings.gd" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n' + "\n".join(values) + "\n",
        encoding="utf8",
        newline="\n",
    )
    print(
        "Elevator:",
        len(visuals),
        "visuals,",
        len(keys),
        "frames,",
        len(platform["child_colliders"]),
        "child colliders",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    export(parser.parse_args().source)
