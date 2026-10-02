"""Render original Object-profile wind events and retain their gameplay call sites."""

import argparse
import json
from pathlib import Path

from import_inari_event_audio import export, sha256

EVENTS = {"WindBuffTrigger": "wind_buff_trigger", "WindBuffRenewal": "wind_buff_renewal"}
BANKS = ("Master", "Master.strings", "SFX_Object", "Snapshot")


def main(source, decompiled, variants):
    trigger = (decompiled / "MoveSpeedChangeTrigger.cs").read_text(encoding="utf8")
    enemy_path = "Enemy.StateMachine/EnemyStateMachine.cs"
    enemy = (decompiled / enemy_path).read_text(encoding="utf8")
    assert 'TryGetValue("WindBuffTrigger"' in trigger
    assert 'TryGetValue("WindBuffRenewal"' in enemy
    output = Path(__file__).resolve().parents[1] / "Original/INARI/Audio"
    export(source, decompiled, output, variants, "Object", EVENTS, "wind", enemy_path, banks=BANKS)
    path = output / "wind_events.json"
    result = json.loads(path.read_text(encoding="utf8"))
    result["source_sha256"]["MoveSpeedChangeTrigger.cs"] = sha256(
        decompiled / "MoveSpeedChangeTrigger.cs"
    )
    for name in ["EnemyRifleMan", "EnemyBowMan", "EnemyBombMan"]:
        relative = f"Enemy/{name}.cs"
        code = (
            (decompiled / relative)
            .read_text(encoding="utf8")
            .split("protected override void OnDead")[1]
        )
        assert code.index("ReturnStoppableSound") < code.index("base.OnDead(damageInfo)")
        result["source_sha256"][relative] = sha256(decompiled / relative)
    path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    parser.add_argument("--variants", type=int, default=8)
    args = parser.parse_args()
    assert args.variants > 0
    main(args.data_directory, args.decompiled_directory, args.variants)
