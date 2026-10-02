"""Localize verified device data, without a level or player.

Geometry, tracks, pixels and audio retain their source data. Only root translation
and inter-device references change: wiring belongs to the host scene's signals.
"""

import copy
import hashlib
import json
from pathlib import Path
from import_inari import dump, multiply
from portable_device_assets import (
    copy_if_changed,
    local_material,
    export_artwork,
    collect_visuals,
)


def export():
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    read = lambda name: json.loads((original / name).read_text(encoding="utf8"))
    machinery = read("machinery.json")
    sprites, materials = read("sprites.json"), read("materials.json")
    hazards = read("portable_hazards.json")
    for kind, level, key in [
        ("MovingPlatform", "level22", "platforms"),
        ("Lever", "level22", "levers"),
        ("MachineDoor", "level5", "doors"),
        ("IceBox", "level5", "ice_boxes"),
        ("WoodDoor", "level2", "doors"),
        ("HeavyDoor", "level22", "doors"),
        ("Checkpoint", hazards["source_scene"], "checkpoint"),
        ("SpikeStrip", hazards["source_scene"], "spike"),
    ]:
        scene = read(level + ".json")
        breakable = kind in ["WoodDoor", "HeavyDoor"]
        collection = scene if breakable else machinery["levels"][level]
        if kind == "MachineDoor":
            collection = collection["battle"]
        record = copy.deepcopy(
            hazards[key] if kind in ["Checkpoint", "SpikeStrip"] else collection[key][0]
        )
        folder = package / "Assets" / kind
        folder.mkdir(parents=True, exist_ok=True)
        if kind == "Checkpoint":
            origin = record["transform"][4:].copy()
            record["transform"][4:] = [0, 0]
            record["spawn_origin"] = [
                record["spawn_origin"][i] - origin[i] for i in range(2)
            ]
            ids = set()
        elif kind == "SpikeStrip":
            origin = hazards["spike_origin"]
            record["transform"][4] -= origin[0]
            record["transform"][5] -= origin[1]
            record["animation"] = {"children": hazards["visual_children"], "states": []}
            # Particle extraction keeps the source hierarchy and subtracts this
            # origin, since the art roots and damage Tilemap are separate objects.
            record["particle_origin_world_pixels"] = origin
            ids = set(hazards["visual_children"])
        elif breakable:
            catalog = read("mechanism_catalog.json")
            component = next(
                item
                for item in catalog["scenes"][level]
                if item["type"] == "InteractiveDoor" and int(item["go"]) == record["go"]
            )
            record["can_shuriken_hit"] = bool(
                component["fields"]["ShurikenComponent"]["canShurikenHit"]
            )
            ids = {piece["go"] for piece in record["pieces"]}
            record["colliders"] = copy.deepcopy(
                [c for c in scene["colliders"] if c.get("go") in ids]
            )
            assert all(c["kind"] == "PolygonCollider2D" for c in record["colliders"])
            points = [
                multiply(
                    c["transform"],
                    [1, 0, 0, 1, p[0] + c["offset"][0], p[1] + c["offset"][1]],
                )[4:]
                for c in record["colliders"]
                for path in c["paths"]
                for p in path
            ]
            origin = [
                (min(p[0] for p in points) + max(p[0] for p in points)) / 2,
                max(p[1] for p in points),
            ]
            for piece in record["pieces"]:
                piece["body_transform"][4] -= origin[0]
                piece["body_transform"][5] -= origin[1]
        elif kind == "MachineDoor":
            wall = next(
                c
                for c in record["colliders"]
                if c["id"] == record["fields"]["invisibleCollider"]["m_PathID"]
            )
            # Use the doorway's bottom centre as a convenient placement pivot.
            # Its world position comes from the source collider, not level constants.
            local = [
                1,
                0,
                0,
                1,
                wall["offset"][0],
                wall["offset"][1] + wall["size"][1] / 2,
            ]
            origin = multiply(wall["transform"], local)[4:]
            ids = set(record["animation"]["children"])
        elif kind == "IceBox":
            origin = record["collider"]["transform"][4:].copy()
            for pose in [record["collider"]["transform"], record["grid_transform"]]:
                pose[4] -= origin[0]
                pose[5] -= origin[1]
            ids = set(record["animation"]["children"])
        else:
            origin = record["transform"][4:]
            record["transform"][4:] = [0, 0]
            ids = set(record["children"])
        visuals = collect_visuals(scene, ids)
        sprite_keys = {v["sprite"] for v in visuals if v["sprite"]}
        track_sets = list(record.get("states", {}).values())
        track_sets.extend(
            s["tracks"] for s in record.get("animation", {}).get("states", [])
        )
        for tracks in track_sets:
            for track in tracks:
                if track["kind"] == "sprite":
                    sprite_keys.update(
                        frame[1] for frame in track["frames"] if frame[1]
                    )
        sprite_info = export_artwork(
            original,
            package,
            folder,
            sprites,
            materials,
            visuals,
            sprite_keys,
            origin,
            hazards["slicing"] if kind == "SpikeStrip" else None,
        )
        for shape in record.get("child_colliders", []) + record.get("colliders", []):
            shape["transform"][4] -= origin[0]
            shape["transform"][5] -= origin[1]
        audio = {}
        extras = {}
        if kind == "Lever":
            record["targets"] = []
            audio["lever"] = read("Audio/machinery_events.json")["groups"]["lever"]
        elif kind == "MachineDoor":
            groups = read("Audio/battle_events.json")["groups"]
            audio = {key: groups[key] for key in ["door_gear_open", "door_gear_close"]}
        elif kind == "IceBox":
            events = read("Audio/ice_events.json")
            audio = events["groups"]
            effects = read("Particles/effects.json")
            burst = copy.deepcopy(effects["effects"]["Eff_Freezing"])
            for emitter in burst["emitters"]:
                name = emitter["texture"]["path"]
                copy_if_changed(original / "Particles" / name, folder / name)
                local_material(emitter["material"], original, package)
            extras = dict(
                rules=machinery["ice_rules"],
                burst=burst,
                gravity=effects["gravity_2d"],
                audio_loop_frames={
                    name: render["timeline_loop_frames"]
                    for name, render in events["renders"].items()
                    if not render["one_shot"]
                },
                effect_sha256=hashlib.sha256(
                    (original / "Particles/effects.json").read_bytes()
                ).hexdigest(),
            )
        elif breakable:
            groups = read("Audio/sounds.json")["groups"]
            audio = {
                key: groups[key]
                for key in ["door_break", "metal_door_hit", "metal_door_break"]
            }
            extras = dict(
                physics=read("door_physics.json"),
                catalog_sha256=hashlib.sha256(
                    (original / "mechanism_catalog.json").read_bytes()
                ).hexdigest(),
                physics_sha256=hashlib.sha256(
                    (original / "door_physics.json").read_bytes()
                ).hexdigest(),
            )
        elif kind in ["Checkpoint", "SpikeStrip"]:
            extras = dict(
                selection=hazards,
                selection_sha256=hashlib.sha256(
                    (original / "portable_hazards.json").read_bytes()
                ).hexdigest(),
            )
            if kind == "SpikeStrip":
                extras["gravity"] = read("Particles/effects.json")["gravity_2d"]
        for files in audio.values():
            for filename in files:
                copy_if_changed(original / "Audio" / filename, folder / filename)
        dump(
            folder / "device.json",
            dict(
                record=record,
                sprites=visuals,
                sprite_info=sprite_info,
                audio=audio,
                source_scene=level,
                source_origin=origin,
                **extras,
                input_sha256={
                    name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                    for name in [
                        "machinery.json",
                        level + ".json",
                        "sprites.json",
                        "materials.json",
                    ]
                },
            ),
        )
        # Defaults are source data, not constants in behaviour scripts.
        settings_name = {
            "MovingPlatform": "PlatformSettings",
            "Lever": "LeverSettings",
            "MachineDoor": "DoorSettings",
            "IceBox": "IceBoxSettings",
            "WoodDoor": "BreakableDoorSettings",
            "HeavyDoor": "BreakableDoorSettings",
            "Checkpoint": "CheckpointSettings",
            "SpikeStrip": "SpikeSettings",
        }[kind]
        fields = record.get("fields", {})
        if kind == "MovingPlatform":
            values = [
                f'travel_offset = Vector2({record["waypoints"][1][0]}, {record["waypoints"][1][1]})',
                f'speed_pixels_per_second = {fields["Speed"] * 16}',
                f'wait_seconds = {fields["WaitTime"]}',
                f'ease_amount = {fields["EaseAmount"]}',
                f'cyclic = {str(bool(fields["Cyclic"])).lower()}',
                f'stop_at_waypoints = {str(bool(fields["IsStopped"])).lower()}',
            ]
        elif kind == "Lever":
            values = [
                f'interaction_mask = {fields["InteractableType"]}',
                f'single_use = {str(bool(fields["isOnce"])).lower()}',
                f'invincible = {str(bool(fields["IsInvincible"])).lower()}',
            ]
        elif kind == "MachineDoor":
            values = [
                f'initial_open = {str(bool(fields["isOpening"])).lower()}',
                f'collider_release_fraction = {fields["colliderTiming"]}',
            ]
        elif kind == "IceBox":
            values = [
                f'radius_pixels = {fields["range"] * record["cell_size"]}',
                f'charge_seconds = {fields["waitingTime"]}',
                f'freeze_seconds = {fields["stunTime"]}',
                f'blink_interval_max = {fields["blinkIntervalMax"]}',
                f'blink_interval_min = {fields["blinkIntervalMin"]}',
                f'outline_fade_seconds = {fields["alphaTime"]}',
            ]
        elif breakable:
            values = [
                f'profile = "{kind}"',
                f'interaction_mask = {record["interactions"]}',
                f'health = {record["health"]}',
                f'invincible = {str(record["invincible"]).lower()}',
                f'fade_seconds = {record["fade_time"]}',
            ]
        elif kind == "Checkpoint":
            values = [
                f'trigger_size = Vector2({record["size"][0]}, {record["size"][1]})',
                f'trigger_offset = Vector2({record["offset"][0]}, {record["offset"][1]})',
                f'spawn_offset = Vector2({record["spawn_origin"][0]}, {record["spawn_origin"][1]})',
                f'facing = {record["facing"]}',
            ]
        else:
            values = [f'damage = {record["damage"]}']
        settings = (
            '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Script" path="{settings_name}.gd" id="1"]\n\n'
            '[resource]\nscript = ExtResource("1")\n' + "\n".join(values) + "\n"
        )
        device_folder = package / "Devices" / ("BreakableDoor" if breakable else kind)
        device_folder.mkdir(parents=True, exist_ok=True)
        settings_file = kind + "Settings" if breakable else settings_name
        (device_folder / (settings_file + ".tres")).write_text(
            settings, encoding="utf8"
        )
        print(kind, len(visuals), "visuals,", len(sprite_keys), "sprite frames")


if __name__ == "__main__":
    export()
