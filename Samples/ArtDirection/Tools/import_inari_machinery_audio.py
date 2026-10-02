"""Render the actual Object/Lever event with the installed FMOD runtime."""

import argparse
from pathlib import Path

from import_inari_event_audio import export


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, args.decompiled_directory,
           Path(__file__).resolve().parents[1] / "Original/INARI/Audio", 2,
           "Object", {"Lever": "lever"}, "machinery", "InteractableTrigger.cs",
           banks=("Master", "Master.strings", "SFX_Object", "Snapshot"))
