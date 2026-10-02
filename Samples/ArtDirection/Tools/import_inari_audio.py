"""Decode selected original FMOD samples without running or modifying INARI.

Requires fmod_toolkit, included with the local UnityPy dependencies. This exports
the source waveforms; FMOD event mixing, spatial effects and random pitch are not
reconstructed by this conversion.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tmp/art-direction/pydeps"))
from fmod_toolkit.fmod import get_pyfmodex_system_instance, pyfmodex, subsound_to_wav

GROUPS = {
    "jump": r"Player_Jump_\d+",
    "double_jump": r"Player_DobuleJump_\d+",
    "wall_jump": r"Player_Wall_Jump",
    "wall_hang": r"Player_Wall_Hang_\d+",
    "wall_up": r"Player_Wall_Up_\d+",
    "dash": r"Player_Dash",
    "land_metal": r"Player_Land_Metal_\d+",
    "land_wood": r"Player_Land_\d+",
    "step_metal": r"Player_Walk_Metal_\d+",
    "step_wood": r"Player_Walk_Wood_\d+",
    "attack": r"Player_Attack_12_\d+",
    "attack3": r"Player_Attack_3_\d+_\d+",
    "heavy_attack": r"Player_Attack_Strong_1_\d+",
    "throw": r"Player_Shuriken_Throw_\d+",
    "teleport": r"Player_Shuriken_Dash_\d+",
    "stick": r"Player_Shuriken_Stick_\d+",
    "bounce": r"Shuriken_Bounce_Stone_\d+",
    "respawn": r"Player_Revival_\d+",
    "hit": r"Player_Hit",
    "door_break": r"Door_Break_\d+",
    "metal_door_break": r"Door_Strong_Break",
    "metal_door_hit": r"Door_Strong_Hit",
    "rifle_reload": r"Monster_Rifle_Reload_\d+",
    "rifle_shot": r"Monster_Rifle_Shot_\d+",
    "rifle_kick": r"Monster_Rifle_Kick(?:_\d+)?",
}


def export_audio(source: Path, output: Path):
    output.mkdir(parents=True, exist_ok=True)
    system, lock = get_pyfmodex_system_instance(2, pyfmodex.flags.INIT_FLAGS.NORMAL)
    groups = {key: [] for key in GROUPS}
    provenance = {}

    for bank_name in ["SFX_Player", "SFX_Shuriken", "SFX_Object", "SFX_Monster"]:
        data = (source / f"{bank_name}.bank").read_bytes()
        start = data.find(b"FSB5")
        if start < 0:
            raise ValueError(f"No FSB sample bank in {bank_name}")

        provenance[bank_name] = hashlib.sha256(data).hexdigest()
        raw = data[start:]
        info = pyfmodex.structure_declarations.CREATESOUNDEXINFO(length=len(raw))
        with lock:
            sound = system.create_sound(raw, pyfmodex.flags.MODE.OPENMEMORY, exinfo=info)
            try:
                for index in range(sound.num_subsounds):
                    sample = sound.get_subsound(index)
                    name = sample.name.decode("utf8")
                    matching = [
                        key for key, pattern in GROUPS.items() if re.fullmatch(pattern, name)
                    ]
                    if not matching:
                        continue

                    filename = name + ".wav"
                    (output / filename).write_bytes(subsound_to_wav(sample))
                    for key in matching:
                        groups[key].append(filename)
            finally:
                sound.release()

    manifest = {"groups": groups, "source_bank_sha256": provenance}
    (output / "sounds.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")
    print(
        f"Exported {sum(len(files) for files in groups.values())} original samples in {len(groups)} groups"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("streaming_assets", type=Path)
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / "Original/INARI/Audio"
    )
    args = parser.parse_args()
    export_audio(args.streaming_assets, args.output)
