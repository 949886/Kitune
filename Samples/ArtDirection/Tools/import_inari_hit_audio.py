"""Render CommonEnemy hit events from the installed game's FMOD banks."""

import argparse
from pathlib import Path

from import_inari_event_audio import BANKS, export

EVENTS = {
    "Hit": "enemy_hit",
    "StackHit1": "enemy_stack_hit_1",
    "StackHit2": "enemy_stack_hit_2",
    "StackHit3": "enemy_stack_hit_3",
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
        "CommonEnemy",
        EVENTS,
        "enemy_hit",
        "Enemy.StateMachine/EnemyStateMachine.cs",
        # CommonEnemy's StackHit references resolve into SFX_Player.bank.
        banks=(*BANKS, "SFX_Player"),
    )
