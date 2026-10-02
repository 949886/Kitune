"""Render source elevator steam and a bounded native motor event timeline.

The motor is stopped by the gameplay owner. Its PCM can repeat for unusually
long rides, with the loop approximation explicitly recorded in the manifest.
"""

import argparse
import json
import hashlib
from pathlib import Path
from import_inari_event_audio import export


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "Original/INARI/Audio"
    export(args.data_directory, args.decompiled_directory, output, 1, "Object",
           {"ElevatorSteam": "elevator_steam", "Elevator": "elevator"}, "elevator", "ElevatorPlatform.cs",
           banks=("Master", "Master.strings", "SFX_Object", "Snapshot"), timeline_loops=("Elevator",))
    path = output / "elevator_events.json"
    data = json.loads(path.read_text(encoding="utf8"))
    name = "InteractableObjectTrigger.cs"
    data["source_sha256"][name] = hashlib.sha256((args.decompiled_directory / name).read_bytes()).hexdigest()
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf8")
