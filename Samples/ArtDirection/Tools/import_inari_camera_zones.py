"""Export all authored camera volumes and source reset rules from the inventory."""

import hashlib
import json
import re
from pathlib import Path
from import_inari import dump, PIXELS_PER_UNIT


def export():
    root = Path(__file__).resolve().parents[1]
    catalog_path = root / "Original/INARI/mechanism_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf8"))
    source = root.parents[1] / "tmp/art-direction/decompiled"
    distance = (source / "CameraDistanceTrigger.cs").read_text(encoding="utf8")
    fixed = (source / "CameraFixTargetTrigger.cs").read_text(encoding="utf8")
    assert "targetGroup.AddMember(target2, 1f, 1f)" in fixed
    assert "targetGroup.AddMember(t, 0f, 1f)" in fixed
    assert "m_MaxDollyIn = 0f" in fixed and "m_MaxDollyOut = 0f" in fixed
    levels = {}
    for scene, entries in catalog["scenes"].items():
        zones = []
        for entry in entries:
            if entry["type"] not in ("CameraDistanceTrigger", "CameraFixTargetTrigger"):
                continue
            if not entry["active"] or not entry["enabled"]:
                continue
            fields = entry["fields"]
            box = next(
                c["data"]
                for c in entry["colliders"]
                if int(c["component_id"]) == fields["boxCollider2D"]["m_PathID"]
            )
            if not box["m_Enabled"]:
                continue
            assert box["m_IsTrigger"]
            zones.append(
                {
                    "go": int(entry["go"]),
                    "id": int(entry["component_id"]),
                    "kind": entry["type"],
                    "fields": fields,
                    "transform": entry["spatial"]["transform"],
                    "size": [box["m_Size"][a] * PIXELS_PER_UNIT for a in "xy"],
                    "offset": [
                        box["m_Offset"]["x"] * PIXELS_PER_UNIT,
                        -box["m_Offset"]["y"] * PIXELS_PER_UNIT,
                    ],
                }
            )
        levels[scene] = zones
    rules = {
        "exit_z_damping": float(
            re.search(r"OnTriggerExit2D[\s\S]*?m_ZDamping = ([\d.]+)f", distance)[1]
        ),
        "soft_zone_delay": float(re.search(r"WaitForSecondsRealtime\(([\d.]+)f\)", fixed)[1]),
    }
    hashes = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest()
        for name in [
            "CameraDistanceTrigger.cs",
            "CameraFixTargetTrigger.cs",
            "CameraFixTargetTriggerManager.cs",
        ]
    }
    for name in ["CinemachineFramingTransposer.cs", "CinemachineTargetGroup.cs"]:
        hashes[name] = hashlib.sha256((source.parent / name).read_bytes()).hexdigest()
    dump(
        root / "Original/INARI/camera_zones.json",
        {
            "levels": levels,
            "rules": rules,
            "implementation_sha256": json.loads(
                (root / "Original/INARI/camera.json").read_text(encoding="utf8")
            )["implementation_sha256"],
            "source_sha256": hashes,
            "catalog_sha256": hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
        },
    )
    print("Camera volumes:", sum(len(zones) for zones in levels.values()))


if __name__ == "__main__":
    export()
