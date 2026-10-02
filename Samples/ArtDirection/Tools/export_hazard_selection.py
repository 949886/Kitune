"""Identify portable trigger instances and their actual authored visual roots.

The spike strip is one connected source polygon, with complete HeatTrap children
inside it. No guessed lethal shape or replacement graphics are introduced.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
from import_inari import UnityPy, PPtr, dump, multiply


def export(source: Path):
    root = Path(__file__).resolve().parents[1]
    profile_file = root / "Profiles/portable_hazards.json"
    profile = json.loads(profile_file.read_text(encoding="utf8"))
    level = profile["scene"]
    original = root / "Original/INARI"
    rules = json.loads(
        (original / "checkpoint_hazards.json").read_text(encoding="utf8")
    )
    scene = json.loads((original / (level + ".json")).read_text(encoding="utf8"))
    checkpoint = copy.deepcopy(
        rules["levels"][level]["checkpoints"][profile["checkpoint_index"]]
    )
    spike = copy.deepcopy(rules["levels"][level]["spikes"][profile["spike_index"]])
    shape = spike["shapes"][profile["spike_shape"]]
    path = shape["paths"][profile["spike_path"]]
    points = [
        multiply(
            spike["transform"],
            [1, 0, 0, 1, p[0] + shape["offset"][0], p[1] + shape["offset"][1]],
        )[4:]
        for p in path
    ]
    bounds = [
        min(p[0] for p in points),
        min(p[1] for p in points),
        max(p[0] for p in points),
        max(p[1] for p in points),
    ]
    # This selected source region is a rectangle; reject a different authoring
    # layout instead of silently widening a non-rectangular shape into a box.
    assert len(points) == 4
    assert all(
        min(abs(p[0] - bounds[0]), abs(p[0] - bounds[2])) < 0.01
        and min(abs(p[1] - bounds[1]), abs(p[1] - bounds[3])) < 0.01
        for p in points
    )
    spike["shapes"] = [dict(offset=shape["offset"], paths=[path])]
    spike["damage"] = rules["spike_damage"]
    env = UnityPy.load(str(source / level))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == level}
    gos = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"
    }
    poses = {
        i: o.read_typetree()
        for i, o in objects.items()
        if o.type.name in ("Transform", "RectTransform")
    }
    by_go = {p["m_GameObject"]["m_PathID"]: i for i, p in poses.items()}
    roots = []
    for visual in scene["sprites"]:
        go = visual.get("go")
        if go not in by_go or not gos[go]["m_Name"].startswith(
            profile["visual_root_prefix"]
        ):
            continue
        parent = poses[by_go[go]]["m_Father"]["m_PathID"]
        if (
            not parent
            or gos[poses[parent]["m_GameObject"]["m_PathID"]]["m_Name"]
            != profile["visual_parent_name"]
        ):
            continue
        x, y = visual.get("spatial", {}).get("transform", visual["transform"])[4:]
        if bounds[0] <= x <= bounds[2] and bounds[1] <= y <= bounds[3]:
            roots.append(go)
    assert roots, "No authored HeatTrap visuals inside the selected lethal polygon"
    children = []
    queue = [by_go[go] for go in roots]
    while queue:
        pose = poses[queue.pop()]
        children.append(pose["m_GameObject"]["m_PathID"])
        queue.extend(p["m_PathID"] for p in pose["m_Children"])
    # Root art is explicitly disabled; its decorative SavePoint subtree is
    # inactive in the shipped instance. Preserve the invisible trigger.
    go = int(checkpoint["go"])
    renderer = next(
        objects[c["component"]["m_PathID"]].read_typetree()
        for c in gos[go]["m_Component"]
        if objects[c["component"]["m_PathID"]].type.name == "SpriteRenderer"
    )
    assert not renderer["m_Enabled"]
    assert not any(v.get("go") == go for v in scene["sprites"])
    # The old scene slice catalog predates this machinery scene. Read the
    # selected source renderers directly, including cropped transparent margins.
    sprites = json.loads((original / "sprites.json").read_text(encoding="utf8"))
    slicing = {}
    source_files = {level}
    for visual in scene["sprites"]:
        if visual.get("go") not in children or visual["mode"] == 0:
            continue
        renderer_obj = next(
            objects[c["component"]["m_PathID"]]
            for c in gos[visual["go"]]["m_Component"]
            if objects[c["component"]["m_PathID"]].type.name == "SpriteRenderer"
        )
        data = renderer_obj.read_typetree()
        assert data["m_SpriteTileMode"] == 0, "Only Continuous tiling is supported"
        native = PPtr(**data["m_Sprite"], assetsfile=renderer_obj.assets_file).deref()
        source_files.add(native.assets_file.name)
        sprite = native.read()
        info = sprites[visual["sprite"]]
        width, height = sprite.m_Rect.width, sprite.m_Rect.height
        offset = sprite.m_RD.textureRectOffset
        trim = [offset.x, height - offset.y - info["size"][1], *info["size"]]
        pivot = [sprite.m_Pivot.x, 1 - sprite.m_Pivot.y]
        expected = [trim[0] - pivot[0] * width, trim[1] - pivot[1] * height]
        assert all(abs(a - b) < 0.001 for a, b in zip(expected, info["offset"]))
        border = sprite.m_Border
        slicing[visual["sprite"]] = dict(
            size=[width, height],
            pivot=pivot,
            border=[border.x, border.w, border.z, border.y],
            trim=trim,
        )
    dump(
        original / "portable_hazards.json",
        dict(
            source_scene=level,
            profile=profile,
            checkpoint=checkpoint,
            spike=spike,
            spike_origin=[(bounds[0] + bounds[2]) / 2, bounds[3]],
            visual_roots=roots,
            visual_children=children,
            checkpoint_renderer_enabled=renderer["m_Enabled"],
            slicing=slicing,
            source_sha256={
                **{
                    name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                    for name in sorted(source_files)
                },
                "profile": hashlib.sha256(profile_file.read_bytes()).hexdigest(),
                "checkpoint_hazards.json": hashlib.sha256(
                    (original / "checkpoint_hazards.json").read_bytes()
                ).hexdigest(),
            },
        ),
    )
    print("Hazard selection:", len(roots), "heat traps,", len(children), "descendants")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    export(parser.parse_args().source)
