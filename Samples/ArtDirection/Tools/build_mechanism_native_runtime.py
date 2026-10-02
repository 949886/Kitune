"""Vendor the exact transitive rendering dependencies into the portable package.

Relative preload/include paths keep the whole folder relocatable. Generated
copies are rebuilt from reviewed runtime sources; hashes prevent silent drift.
"""

import hashlib
import json
import os
import re
from pathlib import Path


def build():
    root = Path(__file__).resolve().parents[3]
    source = root / "Samples/ArtDirection"
    package = root / "Samples/INARIMechanisms"
    destination = package / "Core/Native"
    pending = [
        "Runtime/OriginalParticleEmitter.gd",
        "Shaders/OriginalExposure.gdshader",
        "Runtime/OriginalSceneAnimation.gd",
        "Runtime/InariMovingPlatform.gd",
        "Runtime/InariLever.gd",
        "Runtime/InariMachineDoor.gd",
        "Runtime/InariIceBox.gd",
        "Runtime/OriginalDoor.gd",
        "Runtime/InariCheckpoint.gd",
        "Runtime/StudyHazard.gd",
        "Runtime/OriginalSpriteSlicing.gd",
        "Runtime/InariWindTrigger.gd",
        "Runtime/InariWindBuff.gd",
        "Runtime/InariWindAnimation.gd",
        "Runtime/InariElevator.gd",
        "Runtime/InariScenePortal.gd",
        "Runtime/InariTrialReward.gd",
        "Runtime/InariTrialTerminal.gd",
        "Runtime/InariTimerClock.gd",
        "Runtime/InariTimerDigits.gd",
        "Runtime/InariEncounterClock.gd",
        "Runtime/InariMonsterSpawnTrigger.gd",
        "Runtime/InariCameraRig.gd",
    ]
    hashes = {}
    pattern = re.compile(r'res://Samples/ArtDirection/([^"\n]+)')
    while pending:
        relative = pending.pop()
        if relative in hashes:
            continue
        path = source / relative
        original = path.read_text(encoding="utf8")
        hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        output = destination / relative
        output.parent.mkdir(parents=True, exist_ok=True)

        def relocate(match):
            dependency = match[1]
            if dependency.endswith((".gd", ".gdshader", ".gdshaderinc")):
                pending.append(dependency)
                return Path(
                    os.path.relpath(destination / dependency, output.parent)
                ).as_posix()
            return match[0]

        code = pattern.sub(relocate, original)
        if relative == "Runtime/OriginalAssets.gd":
            code = code.replace(
                'const ROOT := "res://Samples/ArtDirection/Original/INARI/"',
                'static var ROOT: String = (preload("../../../PackageLocation.gd") as Script).resource_path.get_base_dir() + "/Assets/"',
            )
        elif relative == "Runtime/OriginalParticleEmitter.gd":
            code = code.replace(
                'const ROOT := "res://Samples/ArtDirection/Original/INARI/Particles/"',
                'static var ROOT: String = (preload("../../../PackageLocation.gd") as Script).resource_path.get_base_dir() + "/Assets/Particles/"',
            )
        assert "res://Samples/ArtDirection/" not in code, relative
        output.write_text(code, encoding="utf8", newline="\n")
    (package / "Core/native_sources.json").write_text(
        json.dumps(hashes, indent=2) + "\n", encoding="utf8"
    )
    print("Portable native rendering dependencies:", len(hashes))


if __name__ == "__main__":
    build()
