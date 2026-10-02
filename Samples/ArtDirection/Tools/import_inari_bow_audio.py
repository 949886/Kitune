"""Render the source bow events with the installed game's FMOD library and banks."""

import argparse
from pathlib import Path

from import_inari_event_audio import export

EVENTS = {
    "Pull": "bow_pull",
    "Attack": "bow_attack",
    "Shoot": "bow_shoot",
    "DeadVoice": "bow_death",
}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    parser.add_argument("--variants", type=int, default=8)
    args = parser.parse_args()
    assert args.variants > 0
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/Audio",
        args.variants,
        "BowMan",
        EVENTS,
        "bow",
        "Enemy/EnemyBowMan.cs",
    )
