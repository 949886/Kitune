"""Render the shipped ElectroBox loop and charge/explosion FMOD events."""

import argparse
from pathlib import Path
from import_inari_event_audio import export

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/Audio",
        1,
        "Object",
        {"IceMachineLoop": "ice_loop", "IceMachineStart": "ice_start"},
        "ice",
        "ElectroBox.cs",
        banks=("Master", "Master.strings", "SFX_Object", "Snapshot"),
        timeline_loops=("IceMachineLoop",),
    )
