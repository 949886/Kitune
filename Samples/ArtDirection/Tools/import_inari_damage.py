"""Export code-defined player health/blink rules from this build's ILSpy output."""

import argparse
import hashlib
import json
from pathlib import Path
import re


def number(text, pattern):
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"Source rule no longer matches: {pattern}")
    return float(match.group(1))


def export(source, decompiled, output):
    texts = {
        name: (decompiled / name).read_text(encoding="utf8")
        for name in (
            "PlayerStateMachine.cs",
            "OutGameData.cs",
            "PlayerHitState.cs",
            "PlayerDashState.cs",
            "PlayerShurikenDashState.cs",
            "PlayerDashAttackState.cs",
        )
    }
    machine = texts["PlayerStateMachine.cs"]
    modes = texts["OutGameData.cs"]
    result = {
        "normal_hp": int(number(modes, r"defaultModeHp = (\d+)")),
        "story_hp": int(number(modes, r"storyModeHp = (\d+)")),
        "blink_duration": number(machine, r"StartBlinkEffect\(([\d.]+)f\)"),
        "blink_interval": number(machine, r"blinkWait = new WaitForSeconds\(([\d.]+)f\)"),
        "blink_alpha": number(machine, r"cachedSpriteColor.a = \(isFaded \? 1f : ([\d.]+)f\)"),
        "immune_states": {},
        "source_methods": [
            "OutGameData.StoryModeHp",
            "PlayerStateMachine.OnDamaged",
            "PlayerStateMachine.BlinkCoroutine",
            "PlayerHitState.Enter/Update",
        ],
        "source_sha256": hashlib.sha256(
            (source / "Managed/Assembly-CSharp.dll").read_bytes()
        ).hexdigest(),
        "decompiled_sha256": {
            name: hashlib.sha256(text.encode("utf8")).hexdigest() for name, text in texts.items()
        },
    }
    for name, state in (
        ("PlayerDashState.cs", "dash"),
        ("PlayerShurikenDashState.cs", "teleport"),
        ("PlayerDashAttackState.cs", "weakpoint_execution"),
        ("PlayerHitState.cs", "hit"),
    ):
        if not re.search(r"AcceptHealthChange[^}]+return false;", texts[name]):
            raise ValueError(f"Expected immunity missing: {name}")
        result["immune_states"][state] = name.removesuffix(".cs")
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print("Exported original health modes, blink timing and state immunity")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/player_damage.json",
    )
