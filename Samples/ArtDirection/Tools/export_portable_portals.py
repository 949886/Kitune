"""Export every serialized SceneMoveTrigger, including repeat/input variants.

The trigger has no artwork. Destination keys come from the shipped GUID map
and BuildSettings, never from inferred level order or the GameObject name.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path

from import_inari import Importer, UnityPy, dump


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    catalog_path = original / "mechanism_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf8"))
    build = next(
        o.read_typetree()["scenes"]
        for o in UnityPy.load(str(source / "globalgamemanagers")).objects
        if o.type.name == "BuildSettings"
    )
    resources = UnityPy.load(str(source / "resources.assets"))
    guid_map = json.loads(
        next(
            o.read().m_Script
            for o in resources.objects
            if o.type.name == "TextAsset"
            and o.read().m_Name == "Eflatun_SceneReference_SceneGuidToPathMap.generated"
        )
    )
    importer = Importer(source, root / "tmp/art-direction/portal-export")
    records = {}
    hashes = {}
    for level, entries in catalog["scenes"].items():
        selected = [e for e in entries if e["type"] == "SceneMoveTrigger"]
        if not selected:
            continue
        env = UnityPy.load(str(source / level))
        env.typetree_generator = importer.generator
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
        assert (
            len(selected) == 1
        ), "Use component-qualified preset names for multiple exits"
        entry = selected[0]
        fields = copy.deepcopy(entry["fields"])
        assert entry["active"] and entry["enabled"]
        assert fields["triggerLayer"]["m_Bits"] == 64
        for event in ["enterEvent", "exitEvent", "loadEvent"]:
            assert not fields[event]["m_PersistentCalls"]["m_Calls"]
        collider = next(
            c["data"] for c in entry["colliders"] if c["type"] == "BoxCollider2D"
        )
        assert collider["m_IsTrigger"] and collider["m_Enabled"]
        go = objects[int(entry["go"])].read_typetree()
        components = [objects[c["component"]["m_PathID"]] for c in go["m_Component"]]
        assert not any(o.type.name.endswith("Renderer") for o in components)
        transform = next(
            o.read_typetree() for o in components if o.type.name == "Transform"
        )
        markers = []
        for child in transform["m_Children"]:
            marker = objects[child["m_PathID"]].read_typetree()
            marker_go = objects[marker["m_GameObject"]["m_PathID"]].read_typetree()
            assert len(marker_go["m_Component"]) == 1 and not marker["m_Children"]
            markers.append(dict(name=marker_go["m_Name"], transform=marker))
        obj = objects[int(entry["component_id"])]
        reference = importer.pointer(
            obj.assets_file, fields["sceneReferenceData"]
        ).read_typetree()
        scene_path = guid_map[reference["SceneReference"]["guid"]]
        destination = f"level{build.index(scene_path)}"
        pose = entry["spatial"]["transform"].copy()
        assert entry["spatial"]["parallel"] and pose[:4] == [1, 0, 0, 1]
        origin = pose[4:]
        pose[4:] = [0.0, 0.0]
        record = dict(
            go=int(entry["go"]),
            fields=fields,
            destination=destination,
            scene_path=scene_path,
            source_scene=level,
            source_origin=origin,
            markers=markers,
            trigger=dict(
                transform=pose,
                size=[collider["m_Size"][a] * 16 for a in "xy"],
                offset=[
                    collider["m_Offset"]["x"] * 16,
                    -collider["m_Offset"]["y"] * 16,
                ],
            ),
        )
        records[level] = record
        reference_file = (
            importer.pointer(obj.assets_file, fields["sceneReferenceData"])
            .deref()
            .assets_file.name
        )
        for name in [level, reference_file]:
            hashes[name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
        folder = package / "Devices/ScenePortal/Presets"
        folder.mkdir(parents=True, exist_ok=True)
        direction = fields["maintainInputDirection"]
        values = [
            f'trigger_size = Vector2({record["trigger"]["size"][0]}, {record["trigger"]["size"][1]})',
            f'trigger_offset = Vector2({record["trigger"]["offset"][0]}, {record["trigger"]["offset"][1]})',
            f'destination = "{destination}"',
            f'once = {str(bool(fields["once"])).lower()}',
            f'maintain_input = {str(bool(fields["maintainInputOnTransition"])).lower()}',
            f'input_direction = Vector2({direction["x"]}, {-direction["y"]})',
        ]
        (folder / f"{level}.tres").write_text(
            '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
            '[ext_resource type="Script" path="../PortalSettings.gd" id="1"]\n\n'
            '[resource]\nscript = ExtResource("1")\n' + "\n".join(values) + "\n",
            encoding="utf8",
            newline="\n",
        )
    assert len(records) == catalog["counts"]["SceneMoveTrigger"]
    for name in [
        "globalgamemanagers",
        "resources.assets",
        "Managed/UnityEngine.CoreModule.dll",
        "Managed/Assembly-CSharp.dll",
    ]:
        hashes[name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
    rules = json.loads((original / "machinery.json").read_text(encoding="utf8"))
    tween = json.loads((original / "kunai_fade.json").read_text(encoding="utf8"))
    assert tween["ease"] == "OutQuad" and tween["dotween_settings_resource"] is None
    (package / "Devices/ScenePortal/TransitionSettings.tres").write_text(
        '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="TransitionSettings.gd" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n'
        f'fade_seconds = {rules["scene_rules"]["fade_duration"]}\n',
        encoding="utf8",
        newline="\n",
    )
    dump(
        package / "Assets/ScenePortal/device.json",
        dict(
            records=records,
            fade_duration=rules["scene_rules"]["fade_duration"],
            ease=tween["ease"],
            input_sha256={
                name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                for name in [
                    "mechanism_catalog.json",
                    "machinery.json",
                    "kunai_fade.json",
                ]
            },
            source_sha256=hashes,
            behavior_sha256={
                name: hashlib.sha256(
                    (root / "tmp/art-direction/decompiled" / name).read_bytes()
                ).hexdigest()
                for name in [
                    "SceneMoveTrigger.cs",
                    "Trigger.cs",
                    "PlayerInputController.cs",
                    "SceneTranslationUI.cs",
                    "SceneTranslationManager.cs",
                    "PlayerStateMachine.cs",
                ]
            },
            maintained_input_rules={
                "zero_direction": "preserve_previous_input",
                "nonzero_direction": "unity_sign_per_axis",
                "unity_sign_zero": 1,
                "convert_y": -1,
            },
        ),
    )
    print("ScenePortal:", len(records), "source presets; all serialized variants")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    export(parser.parse_args().source)
