"""Audit native StaminaChangeEffectRoutine and its combat callers."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari import dump


def export(source, output):
    player = (source / "PlayerStateMachine.cs").read_text(encoding="utf8")
    method = player.split("public void StaminaChangeEffectRoutine()")[1].split(
        "private void CalculateDashPositionWithGravity"
    )[0]
    assert 'DOTween.Kill("outlineAlphaTween");' in method
    assert "Entity.BuffInfo.MoveSpeedLevel >= Entity.PreviousBuffInfo.MoveSpeedLevel" in method
    assert "DOVirtual.Float(1f, 0f, combatProfile.WindBuffBlinkDuration" in method
    assert 'SetFloat("_InnerOutlineAlpha", value)' in method
    effect = re.search(r'Pop\("([^"]+)"\)', method).group(1)
    assert "obj.transform.SetParent(base.transform);" in method
    tween = json.loads((output / "kunai_fade.json").read_text(encoding="utf8"))
    assert tween["ease"] == "OutQuad" and tween["dotween_settings_resource"] is None
    files = [
        "PlayerStateMachine.cs",
        "PlayerAttackPattern.cs",
        "MoveSpeedChangeTrigger.cs",
        "Enemy.StateMachine/EnemyStateMachine.cs",
        "EnemyShurikenComponent.cs",
    ]
    dump(
        output / "stamina_feedback.json",
        {
            "effect": effect,
            "duration_parameter": "WindBuffBlinkDuration",
            "start": 1.0,
            "end": 0.0,
            "ease": tween["ease"],
            "source_sha256": {
                name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files
            },
            "dotween_source_sha256": tween["source_sha256"]["Managed/DOTween.dll"],
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(args.decompiled_directory, Path(__file__).resolve().parents[1] / "Original/INARI")
