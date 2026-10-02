"""Append original bow animation pixels and renderer dependencies."""

import argparse
from pathlib import Path

from import_inari_enemy_presentation import export

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
        "EnemyBowMan",
        "bow",
        ("Enemy/EnemyBowMan.cs", "RotationPart.cs"),
    )
