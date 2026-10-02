"""Export bomb attack constants from the installed game's decompiled assembly."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari_damage import number


def export(source, decompiled, output):
    names = (
        "Enemy/EnemyBombMan.cs",
        "Enemy.State/EnemyEventChasePattern.cs",
        "Enemy.State/EnemyChasePattern.cs",
        "Enemy.State/EnemyAttackReadyPattern.cs",
        "Enemy.State/EnemyAttackConfirmPattern.cs",
        "EnemyCheckDoorPattern.cs",
        "StateMachine.cs",
    )
    code = {name: (decompiled / name).read_text(encoding="utf8") for name in names}
    bomb = code[names[0]]
    assert "enemyEventChasePattern.IsStop = false" in bomb
    assert "attackTimeBuffer -= Time.deltaTime * base.MovementSpeed" in bomb
    assert "IsSkippAttack" not in bomb
    rules = {
        "chase_sound_frames": [
            float(value)
            for value in re.search(r"new List<float> \{ ([^}]+) \}", bomb)
            .group(1)
            .replace("f", "")
            .split(",")
        ],
        "arrival_distance": number(
            code["StateMachine.cs"], r"GetGrondTilePoint\(\)\.x - pos\.x\) < ([\d.]+)f"
        ),
        "chase_path_distance": number(code[names[1]], r"nextPathDistance = ([\d.]+)f"),
        "targeted_time_scale": number(bomb, r"isTargeted \? ([\d.]+)f"),
        "hit_limit": int(number(bomb, r"hitColliderBuffers = new Collider2D\[(\d+)\]")),
        "player_damage": number(bomb, r"Amount = ([\d.]+)f"),
        "wall_damage": number(bomb, r"RequestDamage\(([\d.]+)f"),
        "ready_glow": number(bomb, r'SetFloat\("_HitEffectGlow", ([\d.]+)f'),
        "effect": "Eff_Enemy_BamBoom_Explosion",
        "door": {
            "damage": number(code["EnemyCheckDoorPattern.cs"], r"Amount = ([\d.]+)f"),
            "chase_skip_ready": False,
            "chase_skip_confirm": False,
            "retreat_skip_ready": False,
            "retreat_skip_confirm": False,
        },
        "source_sha256": {
            name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest() for name in names
        },
    }
    assert 'CreateEffect("' + rules["effect"] + '"' in bomb
    rules["source_sha256"]["Managed/Assembly-CSharp.dll"] = hashlib.sha256(
        (source / "Managed/Assembly-CSharp.dll").read_bytes()
    ).hexdigest()
    (output / "bomb_combat.json").write_text(json.dumps(rules, indent=2) + "\n", encoding="utf8")
    print("Imported original bomb combat constants")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
