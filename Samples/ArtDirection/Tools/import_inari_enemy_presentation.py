"""Append original enemy animation pixels and hidden parts without repacking existing atlases."""

import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

from import_inari import Importer, dump


def read(path):
    return json.loads(path.read_text(encoding="utf8"))


def export(source, decompiled, output, kind, label, source_files):
    sprites = read(output / "sprites.json")
    provenance = read(output / "provenance.json")
    evidence_path = output / f"{label}_presentation.json"
    evidence = read(evidence_path) if evidence_path.exists() else {"added_sprite_sha256": {}}
    # The full scene decoder writes only to a disposable staging directory.
    # Merge selected enemy dependencies explicitly so calibrated camera/material data stays intact.
    with tempfile.TemporaryDirectory(prefix=f"inari-{label}-") as staging:
        staging = Path(staging)
        importer = Importer(source, staging)
        importer.sprites = copy.deepcopy(sprites)
        importer.scene(15)
        decoded = read(staging / "level15.json")
        actors = {item["go"]: item for item in decoded["enemies"] if item["kind"] == kind}
        assert actors, "The selected source scene must contain its selected original enemy"
        if importer.images:
            importer.atlases(start_page=provenance["atlas_count"])
            fresh = read(staging / "provenance.json")
            for page in range(provenance["atlas_count"], fresh["atlas_count"]):
                shutil.copyfile(staging / f"atlas_{page}.png", output / f"atlas_{page}.png")
            provenance["atlas_count"] = fresh["atlas_count"]
            for key, pixels in importer.images.items():
                sprites[key] = importer.sprites[key]
                evidence["added_sprite_sha256"][key] = hashlib.sha256(pixels.tobytes()).hexdigest()
                asset_file = key.rsplit("_", 1)[0] + ".assets"
                provenance["source_files"][asset_file] = hashlib.sha256(
                    (source / asset_file).read_bytes()
                ).hexdigest()

        scene = read(output / "level15.json")
        visual_ids = set()
        for enemy in scene["enemies"]:
            if enemy["go"] not in actors:
                continue
            fresh = actors[enemy["go"]]
            for key in (
                "visuals",
                "gfx_visuals",
                "motion_tracks",
                "combat_animations",
                "ranged_presentation",
            ):
                if key in fresh:
                    enemy[key] = fresh[key]
            visual_ids.update(fresh["visuals"])
        # Existing renderers retain their authored values; new hidden renderers
        # carry original transforms, visibility, material and sorting tuples.
        existing = {item["go"] for item in scene["sprites"]}
        additions = [
            item
            for item in decoded["sprites"]
            if item["go"] in visual_ids and item["go"] not in existing
        ]
        scene["sprites"].extend(additions)
        materials = read(output / "materials.json")
        for item in additions:
            name = item["material"]
            if name not in materials:
                materials[name] = importer.material_details[name]
        # Animation-bound materials can be absent from the static renderer list.
        for enemy in actors.values():
            for state in enemy["combat_animations"].values():
                for track in state.get("tracks", []):
                    if track["kind"] == "material":
                        for _, name in track["frames"]:
                            materials.setdefault(name, importer.material_details[name])
        provenance["sprite_count"] = len(sprites)
        evidence["source_sha256"] = {
            name: hashlib.sha256((source / name).read_bytes()).hexdigest()
            for name in ("level15", "Managed/Assembly-CSharp.dll")
        }
        evidence["decompiled_sha256"] = {
            name: hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
            for name in source_files
        }
        evidence["actors"] = sorted(actors)
        dump(output / "sprites.json", sprites)
        dump(output / "materials.json", materials)
        dump(output / "level15.json", scene)
        dump(output / "provenance.json", provenance)
        dump(evidence_path, evidence)
        for page in sorted({sprites[key]["atlas"] for key in evidence["added_sprite_sha256"]}):
            options = output / f"atlas_{page}.png.import"
            if options.exists():
                options.write_text(
                    options.read_text(encoding="utf8").replace(
                        "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                    ),
                    encoding="utf8",
                )
        print(
            f"Added {len(importer.images)} original sprites and {len(additions)} {label} renderers"
        )
