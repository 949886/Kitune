"""Export the authored timer pair, route and materials without level dependencies."""

import copy
import hashlib
import json
from pathlib import Path
from import_inari import dump
from portable_device_assets import collect_visuals, export_artwork, copy_if_changed


def export():
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    profile = root / "Samples/ArtDirection/Profiles/portable_time_trial.json"
    level = json.loads(profile.read_text())["scene"]
    read = lambda name: json.loads((original / name).read_text(encoding="utf8"))
    machinery = read("machinery.json")
    scene = read(level + ".json")
    timers = machinery["levels"][level]["trials"]["timers"]
    starter = next(t for t in timers if t["kind"] == "TimeAttackTrigger")
    audio = read("Audio/timer_events.json")
    groups = {k: v for k, v in audio["groups"].items() if k.startswith("timer_")}
    for timer in timers:
        kind = "TimerStart" if timer is starter else "TimerFinish"
        folder = package / "Assets" / kind
        folder.mkdir(parents=True, exist_ok=True)
        record = copy.deepcopy(timer)
        origin = record["trigger"]["transform"][4:].copy()
        ids = set(record["animation"]["children"])
        visuals = collect_visuals(scene, ids)
        keys = {v["sprite"] for v in visuals if v["sprite"]}
        tracks = [t for t in scene["animations"] if t.get("go") in ids]
        for state in record["animation"]["states"]:
            tracks.extend(state["tracks"])
        for track in tracks:
            if track["kind"] == "sprite":
                keys.update(frame[1] for frame in track["frames"] if frame[1])
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
        record["trigger"]["transform"][4:] = [0, 0]
        for stop in record.get("camera_stops", []):
            stop["position"] = [a - b for a, b in zip(stop["position"], origin)]
        for files in groups.values():
            for name in files:
                copy_if_changed(original / "Audio" / name, folder / name)
        dump(
            folder / "device.json",
            dict(
                record=record,
                sprites=visuals,
                sprite_info=sprite_info,
                default_tracks=[t for t in scene["animations"] if t.get("go") in ids],
                audio=groups,
                audio_loop_frames={
                    name: info["timeline_loop_frames"]
                    for name, info in audio["renders"].items()
                    if info.get("timeline_loop_frames")
                },
                source_scene=level,
                units=16.0,
                duration=starter["fields"]["setMinute"] * 60
                + starter["fields"]["setSecond"],
                profile_sha256=hashlib.sha256(profile.read_bytes()).hexdigest(),
                input_sha256={
                    name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                    for name in [
                        "machinery.json",
                        level + ".json",
                        "sprites.json",
                        "materials.json",
                        "Audio/timer_events.json",
                    ]
                },
                behavior_sha256={
                    name: hashlib.sha256(
                        (root / "tmp/art-direction/decompiled" / name).read_bytes()
                    ).hexdigest()
                    for name in [
                        "TimeAttackTrigger.cs",
                        "TimeAttackTriggerDest.cs",
                        "TimeAttackTimerBase.cs",
                        "Trigger.cs",
                    ]
                },
            ),
        )
        print(kind, len(visuals), "visuals", len(keys), "frames")
    folder = package / "Devices/TimeTrial"
    folder.mkdir(parents=True, exist_ok=True)
    destination = next(
        t for t in timers if t["id"] == starter["fields"]["dest"]["m_PathID"]
    )
    offset = [
        a - b
        for a, b in zip(
            destination["trigger"]["transform"][4:], starter["trigger"]["transform"][4:]
        )
    ]
    (folder / "TimeTrial.tscn").write_text(
        "[gd_scene load_steps=4 format=3]\n\n"
        '[ext_resource type="Script" path="TimeTrial.gd" id="1"]\n'
        '[ext_resource type="PackedScene" path="TimerStart.tscn" id="2"]\n'
        '[ext_resource type="PackedScene" path="TimerFinish.tscn" id="3"]\n\n'
        '[node name="TimeTrial" type="Node2D"]\nscript = ExtResource("1")\n\n'
        '[node name="Start" parent="." instance=ExtResource("2")]\n\n'
        '[node name="Finish" parent="." instance=ExtResource("3")]\n'
        f"position = Vector2({offset[0]}, {offset[1]})\n",
        encoding="utf8",
        newline="\n",
    )
    fields = starter["fields"]
    (folder / "TrialSettings.tres").write_text(
        '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="TrialSettings.gd" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n'
        f'duration_seconds = {float(fields["setMinute"]*60+fields["setSecond"])}\n'
        f'preview_damping = {float(fields["cameraMoveSpeed"])}\n'
        f'preview_threshold = {float(fields["threshold"])*16}\n',
        encoding="utf8",
        newline="\n",
    )


if __name__ == "__main__":
    export()
