"""Export the installed INARI controller's serialized tuning, without running it.

Run with the original Inari_Data folder. Input bindings can also be refreshed
from ILSpy's PlayerInputActions.cs via --input-actions-source.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tmp/art-direction/pydeps"))
import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator


def clean(value):
    """Keep tuning and curves; discard Unity object headers and opaque pointers."""
    if isinstance(value, list):
        return [clean(item) for item in value]
    if not isinstance(value, dict):
        return value
    if "m_FileID" in value:
        return None
    return {
        key: clean(item)
        for key, item in value.items()
        if key not in {"m_GameObject", "m_Enabled", "m_Script", "m_Name"}
        and not (isinstance(item, dict) and "m_FileID" in item)
    }


def export_controls(source: Path, output: Path, input_source: Path | None):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    result = {"pixels_per_unit": 16, "version": "INARI v0.2.1"}
    classes = {
        "PlayerPhysicsProfile": "physics",
        "PlayerCombatProfile": "combat",
        "PlayerAttackProfile": "attacks",
        "ShurikenObject": "projectile",
    }

    env = UnityPy.load(str(source / "sharedassets1.assets"))
    env.typetree_generator = generator
    for obj in env.objects:
        if obj.type.name == "MonoBehaviour":
            script = obj.parse_monobehaviour_head().m_Script
            if not script:
                continue
            class_name = script.read().m_ClassName
            if class_name in classes:
                result[classes[class_name]] = clean(obj.read_typetree(check_read=False))

        if obj.type.name == "Rigidbody2D" and obj.path_id == 1768:
            result["projectile_body"] = clean(obj.read_typetree())
            result["projectile_layer"] = obj.read().m_GameObject.read().m_Layer

    env = UnityPy.load(str(source / "level1"))
    for obj in env.objects:
        if obj.type.name == "SpriteRenderer":
            data = obj.read_typetree()
            if data["m_GameObject"]["m_PathID"] == 460:
                result["sprite_sort"] = [data["m_SortingLayer"], data["m_SortingOrder"]]

        if obj.type.name == "Transform":
            data = obj.read_typetree()
            if data["m_GameObject"]["m_PathID"] == 460:
                result["gfx_offset"] = data["m_LocalPosition"]

        if obj.type.name != "BoxCollider2D":
            continue
        data = obj.read_typetree()
        if data["m_GameObject"]["m_PathID"] == 218:
            result["body_size"] = data["m_Size"]
            result["body_offset"] = data["m_Offset"]

    env = UnityPy.load(str(source / "globalgamemanagers"))
    layer_names = next(
        o.read_typetree()["layers"] for o in env.objects if o.type.name == "TagManager"
    )
    for obj in env.objects:
        if obj.type.name == "TimeManager":
            result["fixed_timestep"] = obj.read_typetree()["Fixed Timestep"]

        if obj.type.name == "Physics2DSettings":
            mask = obj.read_typetree()["m_LayerCollisionMatrix"][result["projectile_layer"]]
            result["projectile_collision_layers"] = [
                name for index, name in enumerate(layer_names) if mask & (1 << index)
            ]

    if input_source:
        text = input_source.read_text(encoding="utf8")
        match = re.search(r'InputActionAsset.FromJson\(("(?:[^"\\]|\\.)*")\)', text)
        action_asset = json.loads(json.loads(match.group(1)))
        result["bindings"] = action_asset["maps"][0]["bindings"]
    elif output.exists():
        result["bindings"] = json.loads(output.read_text(encoding="utf8"))["bindings"]

    names = ["sharedassets1.assets", "level1", "globalgamemanagers", "Managed/Assembly-CSharp.dll"]
    result["source_sha256"] = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in names
    }
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"Exported INARI physics, combat, projectile and input tuning to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("--input-actions-source", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "Original/INARI/controls.json",
    )
    args = parser.parse_args()
    export_controls(args.data_directory, args.output, args.input_actions_source)
