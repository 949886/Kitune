"""Render original mechanical door, wave arrival and bow alarm events."""

import argparse
from pathlib import Path
from import_inari_event_audio import export

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "Original/INARI/Audio"
    export(
        args.data_directory,
        args.decompiled_directory,
        output,
        1,
        "Object",
        {
            "DoorGearOpen": "door_gear_open",
            "DoorGearClose": "door_gear_close",
            "StampDown": "wave_stamp",
            "StampRiffle": "wave_rope",
        },
        "battle",
        "Door.cs",
        banks=("Master", "Master.strings", "SFX_Object", "Snapshot"),
    )
    export(
        args.data_directory,
        args.decompiled_directory,
        output,
        1,
        "BowMan",
        {"Alarm": "bow_alarm"},
        "battle_bow",
        "Enemy/EnemyBowMan.cs",
    )
