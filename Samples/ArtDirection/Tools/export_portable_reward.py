"""Localize the authored HiddenItem trigger and its seven homing fragments."""

import argparse
import copy
import hashlib
import json
import struct
from pathlib import Path
from import_inari import dump, UnityPy
from extract_inari_uv_programs import extract
from portable_device_assets import collect_visuals, export_artwork, copy_if_changed


def export(source: Path):
    root = Path(__file__).resolve().parents[3]
    original = root / "Samples/ArtDirection/Original/INARI"
    package = root / "Samples/INARIMechanisms"
    folder = package / "Assets/HiddenReward"
    folder.mkdir(parents=True, exist_ok=True)
    profile_file = root / "Samples/ArtDirection/Profiles/portable_reward.json"
    profile = json.loads(profile_file.read_text(encoding="utf8"))
    read = lambda name: json.loads((original / name).read_text(encoding="utf8"))
    machinery = read("machinery.json")
    level = profile["scene"]
    record = copy.deepcopy(
        machinery["levels"][level]["trials"]["rewards"][profile["reward_index"]]
    )
    scene = read(level + ".json")
    ids = set(record["children"])
    origin = record["trigger"]["transform"][4:].copy()
    visuals = collect_visuals(scene, ids)
    assert all(v.get("mode", 0) == 0 for v in visuals)
    tracks = [t for t in scene["animations"] if t.get("go") in ids]
    keys = {v["sprite"] for v in visuals if v["sprite"]}
    for track in tracks:
        if track["kind"] == "sprite":
            keys.update(f[1] for f in track["frames"] if f[1])
    sprite_info = export_artwork(
        original,
        package,
        folder,
        read("sprites.json"),
        read("materials.json"),
        visuals,
        keys,
        origin,
    )
    env = UnityPy.load(str(source / level))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
    source_hashes = {level: hashlib.sha256((source / level).read_bytes()).hexdigest()}
    for visual in visuals:
        renderer = next(
            o
            for o in objects.values()
            if o.type.name == "SpriteRenderer"
            and o.read_typetree()["m_GameObject"]["m_PathID"] == visual["go"]
        )
        material = renderer.read().m_Materials[0].read()
        shader = material.m_Shader.read()
        if shader.m_ParsedForm.m_Name != "Shader Graphs/SquareDistortion":
            continue
        raw = material.object_reader.read_typetree()
        sprite = renderer.read().m_Sprite.read()
        rd = sprite.object_reader.read_typetree()["m_RD"]
        vertex = rd["m_VertexData"]
        assert vertex["m_Channels"][0] == {
            "stream": 0,
            "offset": 0,
            "format": 0,
            "dimension": 3,
        }
        assert all(
            c["dimension"] == 0 or (i == 0 or c["stream"] != 0)
            for i, c in enumerate(vertex["m_Channels"])
        )
        positions = [
            struct.unpack_from("<fff", bytes(vertex["m_DataSize"]), i * 12)
            for i in range(vertex["m_VertexCount"])
        ]
        assert all(p[2] == 0 for p in positions)
        texture = sprite.m_RD.texture.read()
        transform = sprite.m_RD.uvTransform
        uvs = [
            [
                (p[0] * transform.x + transform.y) / texture.m_Width,
                (p[1] * transform.z + transform.w) / texture.m_Height,
            ]
            for p in positions
        ]
        indices = list(
            struct.unpack(
                "<" + "H" * (len(rd["m_IndexBuffer"]) // 2), bytes(rd["m_IndexBuffer"])
            )
        )
        game_object = objects[visual["go"]].read_typetree()
        transform = next(
            objects[c["component"]["m_PathID"]].read_typetree()
            for c in game_object["m_Component"]
            if objects[c["component"]["m_PathID"]].type.name == "Transform"
        )
        programs = {}
        audit = root / "tmp/art-direction/reward-distortion"
        audit.mkdir(exist_ok=True)
        for stage in ["vertex", "fragment"]:
            code, params, programs[stage] = extract(shader, set(), stage)
            (audit / (stage + ".dxbc")).write_bytes(code)
            (audit / (stage + ".params")).write_bytes(params)
        visual["square_distortion"] = dict(
            parameters=dict(raw["m_SavedProperties"]["m_Floats"]),
            flow=dict(raw["m_SavedProperties"]["m_Colors"])["_DistortionFlowSpeed"],
            positions=[[p[0] * 16, -p[1] * 16] for p in positions],
            uvs=uvs,
            indices=indices,
            initial_scale=[transform["m_LocalScale"][a] for a in "xy"],
            programs=programs,
        )
        for obj in [
            material.object_reader,
            shader.object_reader,
            sprite.object_reader,
            texture.object_reader,
        ]:
            name = obj.assets_file.name
            source_hashes[name] = hashlib.sha256(
                (source / name).read_bytes()
            ).hexdigest()
    record["trigger"]["transform"][4:] = [0.0, 0.0]
    for light in record["lights"]:
        light["definition"] = copy.deepcopy(scene["lights"][light["index"]])
        light["definition"]["enabled"] = True
        for pose in [
            light["transform"],
            light["definition"]["transform"],
            light["definition"]["spatial"]["transform"],
        ]:
            pose[4] -= origin[0]
            pose[5] -= origin[1]
    record["animation"] = {"children": sorted(ids), "states": []}
    record["particle_origin_world_pixels"] = origin
    audio = read("Audio/timer_events.json")
    groups = {k: v for k, v in audio["groups"].items() if k.startswith("reward_")}
    for files in groups.values():
        for name in files:
            copy_if_changed(original / "Audio" / name, folder / name)
    dump(
        folder / "device.json",
        dict(
            record=record,
            sprites=visuals,
            sprite_info=sprite_info,
            default_tracks=tracks,
            audio=groups,
            rules=machinery["trial_rules"],
            source_scene=level,
            units=16.0,
            gravity=read("Particles/effects.json")["gravity_2d"],
            input_sha256={
                name: hashlib.sha256((original / name).read_bytes()).hexdigest()
                for name in [
                    "machinery.json",
                    level + ".json",
                    "sprites.json",
                    "materials.json",
                    "Audio/timer_events.json",
                    "Particles/effects.json",
                ]
            },
            profile_sha256=hashlib.sha256(profile_file.read_bytes()).hexdigest(),
            source_sha256=source_hashes,
            behavior_sha256={
                name: hashlib.sha256(
                    (root / "tmp/art-direction/decompiled" / name).read_bytes()
                ).hexdigest()
                for name in [
                    "RewardObserver.cs",
                    "ShurikenChargePoint.cs",
                    "SimpleAnimator.cs",
                    "Trigger.cs",
                ]
            },
        ),
    )
    settings = package / "Devices/HiddenReward"
    settings.mkdir(parents=True, exist_ok=True)
    (settings / "RewardSettings.tres").write_text(
        '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="RewardSettings.gd" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\nreward_amount = 1\n'
        f'currency_per_fragment = {machinery["trial_rules"]["charge_value"]}\n',
        encoding="utf8",
        newline="\n",
    )
    print(
        "HiddenReward:",
        len(visuals),
        "visuals,",
        len(keys),
        "sprite frames,",
        len(record["charges"]),
        "fragments",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    export(parser.parse_args().source)
