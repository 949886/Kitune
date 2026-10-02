"""Export source checkpoints and spike rules from the audited scene inventory."""

import hashlib
import json
import re
from pathlib import Path

from import_inari import dump, PIXELS_PER_UNIT


def export():
    root = Path(__file__).resolve().parents[1]
    catalog_path = root / "Original/INARI/mechanism_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf8"))
    profiles = json.loads((root / "Profiles/levels.json").read_text(encoding="utf8"))
    playable_sources = {Path(item["scene_data"]).stem for item in profiles if "scene_data" in item}
    playable_sources.update(Path(entry["scene_data"]).stem for item in profiles
                            for entry in item.get("practice_entries", []) if "scene_data" in entry)
    mechanism_scenes = json.loads((root / "Profiles/mechanism_levels.json").read_text(encoding="utf8"))
    playable_sources.update(f"level{number}" for number in mechanism_scenes["scenes"])
    decompiled = root.parents[1] / "tmp/art-direction/decompiled"
    spike = (decompiled / "SettedSpike.cs").read_text(encoding="utf8")
    damage = re.findall(r"Amount = ([\d.]+)f", spike)
    assert len(damage) == 2 and damage[0] == damage[1]
    assert "OnTriggerStay2D" in spike and "!playerStateMachine.Entity.IsInvincible" in spike
    levels = {}
    for scene, entries in catalog["scenes"].items():
        if scene not in playable_sources:
            continue
        saves, spikes = [], []
        for item in entries:
            if not item["active"] or not item["enabled"]:
                continue
            if item["type"] == "SettedSpike":
                shapes = []
                for collider in item["colliders"]:
                    value = collider["data"]
                    if not value["m_Enabled"] or value["m_UsedByComposite"]:
                        continue
                    assert value["m_IsTrigger"]
                    assert collider["type"] == "PolygonCollider2D", collider["type"]
                    shapes.append({"offset": [value["m_Offset"]["x"] * PIXELS_PER_UNIT,
                                               -value["m_Offset"]["y"] * PIXELS_PER_UNIT],
                                   "paths": [[[p["x"] * PIXELS_PER_UNIT, -p["y"] * PIXELS_PER_UNIT]
                                              for p in path] for path in value["m_Points"]["m_Paths"]]})
                spikes.append({"go": item["go"], "transform": item["spatial"]["transform"], "shapes": shapes})
            if item["type"] != "InteractiveSaveTrigger":
                continue
            fields = item["fields"]
            assert fields["triggerLayer"]["m_Bits"] == 64
            collider = next(c["data"] for c in item["colliders"] if c["type"] == "BoxCollider2D")
            assert collider["m_IsTrigger"] and collider["m_Enabled"]
            saves.append({"go": item["go"], "id": fields["id"], "transform": item["spatial"]["transform"],
                          "size": [collider["m_Size"][a] * PIXELS_PER_UNIT for a in "xy"],
                          "offset": [collider["m_Offset"]["x"] * PIXELS_PER_UNIT, -collider["m_Offset"]["y"] * PIXELS_PER_UNIT],
                          "spawn_origin": item["transform_refs"]["spawnPoint"]["transform"][4:],
                          "facing": 1 if fields["lookRight"] else -1,
                          "source_unused_add_stamina": fields["addStamina"],
                          "save_events": fields["OnSaveTriggerEnter"]})
        levels[scene] = {"checkpoints": saves, "spikes": spikes}
    files = ["SettedSpike.cs", "InteractiveSaveTrigger.cs", "Trigger.cs", "PlayerRunTimeData.cs", "SceneRoot.cs"]
    dump(root / "Original/INARI/checkpoint_hazards.json", {
        "levels": levels, "spike_damage": float(damage[0]),
        "catalog_sha256": hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
        "source_sha256": {name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest() for name in files}})
    print("Exported checkpoints:", sum(len(x["checkpoints"]) for x in levels.values()))


if __name__ == "__main__":
    export()
