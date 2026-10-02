"""Render the source bomb events with the installed game's FMOD library and banks."""

import argparse
from pathlib import Path

from import_inari_event_audio import export

EVENTS = {
    "PatrolVoice": "bomb_patrol_voice",
    "Chase": "bomb_chase",
    "ExplosionReady": "bomb_ready",
    "ExplosionReadyLeg": "bomb_ready_leg",
    "Explosion": "bomb_explosion",
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
        "BombMan",
        EVENTS,
        "bomb",
        "Enemy/EnemyBombMan.cs",
    )
    # Ordinary deaths also invoke the base class's CommonEnemy event. Self
    # destruction explicitly excludes it because DamageInfo.Source == Entity.
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/Audio",
        args.variants,
        "CommonEnemy",
        {"Death": "enemy_common_death"},
        "enemy_common",
        "Enemy.StateMachine/EnemyStateMachine.cs",
    )
