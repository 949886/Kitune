"""Audit ResetShuriken's fade chain and the shipped DOTween scheduling defaults."""

import argparse
import hashlib
import re
from pathlib import Path
from import_inari import UnityPy, dump


def export(source, decompiled, audit, output):
    player = (decompiled / "PlayerStateMachine.cs").read_text(encoding="utf8")
    shuriken = (decompiled / "ShurikenObject.cs").read_text(encoding="utf8")
    tween = (audit / "DOTween.cs").read_text(encoding="utf-8-sig")
    manager = (audit / "TweenManager.cs").read_text(encoding="utf-8-sig")
    defaults = re.search(r"defaultEaseType = Ease.(\w+);", tween).group(1)
    assert defaults == "OutQuad" and "defaultUpdateType = UpdateType.Normal;" in tween
    assert 'spriteRenderer.material.DOFloat(1f, "_HitEffectBlend", brightDuration)' in shuriken
    assert "spriteRenderer.DOFade(0f, fadeOutDuration).OnComplete(CleanUp);" in shuriken
    assert "int num = _maxActiveLookupId + 1;" in manager
    clear = player.split("private void OnInputShurikenClear()")[1].split("private void")[0]
    assert "base.CurrentStateType != PlayerStateType.Throw" in clear and "ResetShuriken();" in clear
    resources = next(
        o.read_typetree()
        for o in UnityPy.load(str(source / "globalgamemanagers")).objects
        if o.type.name == "ResourceManager"
    )
    assert not any("dotweensettings" in name.lower() for name, pointer in resources["m_Container"])
    files = {
        "ShurikenObject.cs": decompiled / "ShurikenObject.cs",
        "PlayerStateMachine.cs": decompiled / "PlayerStateMachine.cs",
        "SkillObject.cs": decompiled / "SkillObject.cs",
        "DOTween.cs": audit / "DOTween.cs",
        "TweenManager.cs": audit / "TweenManager.cs",
    }
    for name in ("globalgamemanagers", "Managed/Assembly-CSharp.dll", "Managed/DOTween.dll"):
        files[name] = source / name
    dump(
        output,
        {
            "ease": defaults,
            "update_type": "Normal",
            "next_tween_starts_next_update": True,
            "cancel_excluded_state": "Throw",
            "uses_global_time": True,
            "dotween_settings_resource": None,
            "source_sha256": {
                name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()
            },
        },
    )
    print("Native kunai fade: OutQuad, two Normal updates, no DOTweenSettings resource")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    parser.add_argument("dotween_sources", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        args.dotween_sources,
        Path(__file__).resolve().parents[1] / "Original/INARI/kunai_fade.json",
    )
