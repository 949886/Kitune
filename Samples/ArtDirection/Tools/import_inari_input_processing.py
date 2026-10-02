"""Recover the preloaded InputSettings and the stick processor chains."""

import argparse
import hashlib
import json
import re
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, dump


def export(source, decompiled, runtime_sources, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "globalgamemanagers"))
    env.typetree_generator = generator
    player_settings = next(obj for obj in env.objects if obj.type.name == "PlayerSettings")
    candidates = []
    for pointer in player_settings.read_typetree()["preloadedAssets"]:
        obj = PPtr(**pointer, assetsfile=player_settings.assets_file).deref()
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if head.m_Script.read().m_ClassName == "InputSettings":
            candidates.append(obj)
    assert len(candidates) == 1, "The player must preload exactly one InputSettings"
    settings = candidates[0]
    values = settings.read_typetree(check_read=False)
    actions_source = (decompiled / "PlayerInputActions.cs").read_text(encoding="utf8")
    literal = re.search(r'InputActionAsset.FromJson\(("(?:[^"\\]|\\.)*")\)', actions_source)
    asset = json.loads(json.loads(literal.group(1)))
    action_map = next(
        m for m in asset["maps"] if any(a["name"] == "GP_RightStick" for a in m["actions"])
    )
    sticks = {}
    gamepad = (runtime_sources / "gamepad_state.cs").read_text(encoding="utf8")
    controller = (decompiled / "PlayerInputController.cs").read_text(encoding="utf8")
    for key, action_name, control in [
        ("right_stick", "GP_RightStick", "rightStick"),
        ("left_stick", "GP_LeftStick", "leftStick"),
    ]:
        action = next(a for a in action_map["actions"] if a["name"] == action_name)
        bindings = [b for b in action_map["bindings"] if b["action"] == action_name]
        assert len(bindings) == 1 and bindings[0]["path"] == "<Gamepad>/" + control
        assert (
            action["type"] == "Value" and not action["processors"] and not bindings[0]["processors"]
        )
        attribute = re.search(
            r"\[InputControl\(([^\]]+)\)\]\s*public Vector2 " + control + ";", gamepad
        ).group(1)
        processor = re.search(r'processors = "([^"]+)"', attribute).group(1)
        assert processor == "stickDeadzone"
        sticks[key] = {
            "action": action,
            "binding": bindings[0],
            "processor": processor,
            "minimum": values["m_DefaultDeadzoneMin"],
            "maximum": values["m_DefaultDeadzoneMax"],
        }
    left_body = controller.split("private void HandleGamePadLeftStick(Vector2 direction)")[1].split(
        "private void"
    )[0]
    sticks["left_stick"]["activation_threshold"] = float(
        re.search(r"direction.magnitude > ([0-9.]+)f", left_body).group(1)
    )
    sticks["left_stick"]["vertical_threshold"] = float(
        re.search(r"Mathf.Abs\(direction.y\) > ([0-9.]+)f", left_body).group(1)
    )
    assert "InputX = Mathf.Sign(direction.x);" in left_body
    assert "if (InputY < 0f)" in left_body and "InputX = 0f;" in left_body
    startup = (runtime_sources / "input_system.cs").read_text(encoding="utf8")
    assert "Resources.FindObjectsOfTypeAll<InputSettings>().FirstOrDefault()" in startup
    minimum = values["m_DefaultDeadzoneMin"]
    maximum = values["m_DefaultDeadzoneMax"]
    assert 0 <= minimum < maximum
    files = [
        "globalgamemanagers",
        "globalgamemanagers.assets",
        "Managed/Unity.InputSystem.dll",
        "Managed/Assembly-CSharp.dll",
    ]
    hashes = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files}
    for name in ["PlayerInputActions.cs", "InputManager.cs", "PlayerInputController.cs"]:
        hashes[name] = hashlib.sha256((decompiled / name).read_bytes()).hexdigest()
    for name in [
        "gamepad_state.cs",
        "stick_deadzone.cs",
        "input_settings.cs",
        "input_system.cs",
        "input_action_state.cs",
        "vector2_control.cs",
    ]:
        hashes[name] = hashlib.sha256((runtime_sources / name).read_bytes()).hexdigest()
    dump(
        output,
        {
            "settings": {
                "name": values["m_Name"],
                "object_id": str(settings.path_id),
                "preloaded": True,
            },
            **sticks,
            "source_sha256": hashes,
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    parser.add_argument("input_system_sources", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        args.input_system_sources,
        Path(__file__).resolve().parents[1] / "Original/INARI/input_processing.json",
    )
