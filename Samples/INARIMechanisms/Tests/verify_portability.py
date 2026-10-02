"""Copy this whole package under a different name in a fresh Godot project.

Requires Python standard library and a supplied Godot executable. It does not
import the original game or any Rossi tools. The sandbox is preserved for review.
"""

import argparse
import array
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave


def verify(godot: Path, output: Path):
    package = Path(__file__).resolve().parents[1]
    if output.resolve().is_relative_to(package):
        raise ValueError("Choose an output directory outside the copied package.")
    project = Path(tempfile.mkdtemp(prefix="inari-copy-", dir=output))
    installed = project / "Nested/RenamedDevices"
    shutil.copytree(package, installed, ignore=shutil.ignore_patterns("__pycache__", "*.uid", "*.import"))
    (project / "project.godot").write_text(
        '[application]\nconfig/name="INARI portable validation"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
        encoding="utf8",
    )
    base = [
        str(godot.resolve()),
        "--path",
        str(project),
        "--rendering-method",
        "gl_compatibility",
    ]

    def run(name, arguments, success=None):
        log = project / (name + ".log")
        result = subprocess.run(
            base + arguments + ["--log-file", str(log)],
            capture_output=True,
            encoding="utf8",
            errors="replace",
            timeout=60,
            env=dict(os.environ, INARI_AUDIO_OUTPUT="silent"),
        )
        combined = result.stdout + result.stderr
        failed_resource = any(
            marker in combined
            for marker in [
                "SCRIPT ERROR",
                "SHADER ERROR",
                "Failed loading resource:",
                "Error loading resource:",
            ]
        )
        if (
            result.returncode
            or failed_resource
            or (success and success not in combined)
        ):
            raise RuntimeError(f"{name} failed; inspect {log}\n{combined[-3000:]}")
        print(name, "PASS", flush=True)

    # Allow the editor's first GDExtension registration to finish its startup.
    run("import", ["--headless", "--editor", "--import", "--quit-after", "3"])
    for name, marker in [
        ("SteamJetProbe", "STEAM_JET_PROBE_PASS"),
        ("DisappearingPlatformProbe", "PORTABLE_DISAPPEARING_PLATFORM_PASS"),
        ("PlatformWorkshopProbe", "PORTABLE_PLATFORM_PROBE_PASS"),
        ("MachineDoorProbe", "PORTABLE_DOOR_PROBE_PASS"),
        ("IceBoxProbe", "PORTABLE_ICE_PROBE_PASS"),
        ("BreakableDoorProbe", "PORTABLE_BREAKABLE_DOOR_PASS"),
        ("CheckpointHazardProbe", "PORTABLE_CHECKPOINT_HAZARD_PASS"),
        ("WindStationProbe", "PORTABLE_WIND_STATION_PASS"),
        ("ElevatorWorkshopProbe", "PORTABLE_ELEVATOR_PASS"),
        ("ScenePortalProbe", "PORTABLE_SCENE_PORTAL_PASS"),
        ("HiddenRewardProbe", "PORTABLE_HIDDEN_REWARD_PASS"),
        ("TimeTrialWorkshopProbe", "PORTABLE_TIME_TRIAL_PASS"),
        ("BattleEncounterProbe", "PORTABLE_BATTLE_ENCOUNTER_PASS"),
        ("MonsterSpawnTriggerProbe", "PORTABLE_MONSTER_SPAWN_TRIGGER_PASS"),
        ("RepeatingSpawnerProbe", "PORTABLE_REPEATING_SPAWNER_PASS"),
        ("ThresholdEncounterProbe", "PORTABLE_THRESHOLD_ENCOUNTER_PASS"),
        ("SceneObserverProbe", "PORTABLE_SCENE_OBSERVER_PASS"),
        ("ArrivalEffectProbe", "PORTABLE_ARRIVAL_EFFECT_PASS"),
        ("CameraZoneProbe", "PORTABLE_CAMERA_ZONE_PASS"),
        ("EnvironmentAudioProbe", "PORTABLE_ENVIRONMENT_AUDIO_PASS"),
        ("ShurikenDistanceProbe", "PORTABLE_SHURIKEN_DISTANCE_PASS"),
    ]:
        run(
            name,
            [
                "--fixed-fps",
                "60",
                "--script",
                f"res://Nested/RenamedDevices/Tests/{name}.gd",
            ],
            marker,
        )
    verify_waveform(project / "environment-validation.wav")
    print("Review project:", project)


def verify_waveform(path: Path):
    with wave.open(str(path), "rb") as audio:
        assert audio.getframerate() == 48000 and audio.getsampwidth() == 2
        channels = audio.getnchannels()
        samples = array.array("h", audio.readframes(audio.getnframes()))
    # The first second resets every ambient parameter. Out4 is then enabled
    # for four seconds before any BGM begins: measure that actual engine output.
    quiet = samples[:48000 * channels]
    ambient = samples[48000 * 2 * channels:48000 * 5 * channels]
    rms = lambda values: math.sqrt(sum(float(x) ** 2 for x in values) / len(values))
    assert rms(ambient) > 20 and rms(ambient) > rms(quiet) * 2
    print(f"FMOD waveform PASS ambient_rms={rms(ambient):.2f} baseline_rms={rms(quiet):.2f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    verify(args.godot, args.output.resolve())
