"""Scene-local enemy bindings for spawned waves, independent of level15 IDs.

The battle exporter supplies the actual selected actors. Inactive weak-point
branches are imported for runtime activation, never baked into the idle pose.
"""

import hashlib
from unity_scene_spatial import WorldTransforms
from unity_scene_animation import animator_tracks, target_paths
from import_inari import rgba


def collect(importer, objects, gos, poses, by_go, actor_ids):
    world = WorldTransforms(poses)
    result, visuals = {}, set()

    def branch(go):
        found = [go]
        for ref in poses[by_go[go]]["m_Children"]:
            child = poses[ref["m_PathID"]]["m_GameObject"]["m_PathID"]
            if gos[child]["m_IsActive"]:
                found.extend(branch(child))
        return found

    for actor_id in actor_ids:
        obj = objects[actor_id]
        raw = obj.read_typetree()
        go = raw["m_GameObject"]["m_PathID"]
        read = lambda p: importer.pointer(obj.assets_file, p).read_typetree()
        entity = read(raw["Entity"])
        controller = read(entity["EnemyWeakPointComponent"]["_enemyWeakpointController"])
        stacks = [branch(p["m_PathID"]) for p in controller["weakPointStackObjects"]]
        range_go = controller["weakPointRange"]["m_PathID"]
        members = branch(range_go)
        outlines = [
            read(p)["m_GameObject"]["m_PathID"] for p in raw["otherRenderers"] if p["m_PathID"]
        ]
        animation = []
        for member in members:
            for ref in gos[member]["m_Component"]:
                animator = objects[ref["component"]["m_PathID"]]
                if animator.type.name == "Animator" and animator.read().m_Enabled:
                    animation.extend(
                        animator_tracks(
                            importer,
                            animator,
                            target_paths(member, gos, poses, by_go),
                            poses,
                            by_go,
                        )
                    )
        result[go] = {
            "weakpoint_binding": {
                "stacks": stacks,
                "range_members": members,
                "outline_visuals": outlines,
                "range_transform": world.sprite_plane(by_go[range_go], 16)["transform"],
                "range_collider": read(controller["weakPointRangeCollider"]),
                "animations": animation,
            },
            "hit_visuals": sorted(set(outlines + [read(raw["GFX"])["m_GameObject"]["m_PathID"]])),
        }
        result[go]["outline_materials"] = {}
        for pointer in raw["otherRenderers"]:
            if not pointer["m_PathID"]:
                continue
            renderer = importer.pointer(obj.assets_file, pointer).deref()
            for ref in renderer.read_typetree()["m_Materials"]:
                mat = importer.pointer(renderer.assets_file, ref).read_typetree()
                floats = dict(mat["m_SavedProperties"]["m_Floats"])
                colors = dict(mat["m_SavedProperties"]["m_Colors"])
                assert {"OUTBASE_ON", "OUTBASEPIXELPERF_ON"} <= set(mat["m_ValidKeywords"])
                result[go]["outline_materials"][mat["m_Name"]] = {
                    "color": rgba(colors["_OutlineColor"]),
                    "alpha": floats["_OutlineAlpha"],
                    "glow": floats["_OutlineGlow"],
                    "pixel_width": floats["_OutlinePixelWidth"],
                }
        visuals.update(members)
        for group in stacks:
            visuals.update(group)
        kind = obj.parse_monobehaviour_head().m_Script.read().m_ClassName
        if kind == "EnemyBowMan":
            target = by_go[raw["attackPoint"]["m_PathID"]]
            # Resolve to a SpriteRenderer ancestor, as the calibrated bow importer.
            anchor = target
            while not any(
                objects[p["component"]["m_PathID"]].type.name == "SpriteRenderer"
                for p in gos[poses[anchor]["m_GameObject"]["m_PathID"]]["m_Component"]
            ):
                anchor = poses[anchor]["m_Father"]["m_PathID"]
                assert anchor
            point = world.sprite_plane(target, 16)["transform"]
            a, b, c, d, x, y = world.sprite_plane(anchor, 16)["transform"]
            dx, dy = point[4] - x, point[5] - y
            result[go]["bow_binding"] = {
                "anchor_go": poses[anchor]["m_GameObject"]["m_PathID"],
                "attack_point_go": raw["attackPoint"]["m_PathID"],
                "anchor_local": [
                    (d * dx - c * dy) / (a * d - b * c),
                    (-b * dx + a * dy) / (a * d - b * c),
                ],
                "source_position": point[4:],
                "can_alarm": raw["IsCanAlarm"],
                "run_away_weight": raw["RunAwayWeight"],
                "confirm_effect_frame": raw["AttackConfirmEffectFrame"],
            }
        if kind == "EnemyRifleMan":
            lines = {}
            rotating = {
                read(p)["m_GameObject"]["m_PathID"]
                for p in raw["rotationPart"]["RotationSpriteInfos"]["keys"]
            }
            for label, field in [("aim", "LineRenderer"), ("tracer", "AttackRangeLineRenderer")]:
                renderer_obj = importer.pointer(obj.assets_file, raw[field]).deref()
                renderer = renderer_obj.read_typetree()
                line_go = renderer["m_GameObject"]["m_PathID"]
                anchor = by_go[line_go]
                while poses[anchor]["m_GameObject"]["m_PathID"] not in rotating:
                    anchor = poses[anchor]["m_Father"]["m_PathID"]
                    assert anchor
                material_obj = importer.pointer(
                    renderer_obj.assets_file, renderer["m_Materials"][0]
                ).deref()
                material = material_obj.read_typetree()
                props = material["m_SavedProperties"]
                colors = dict(props["m_Colors"])
                floats = dict(props["m_Floats"])
                pointer = dict(props["m_TexEnvs"])["_MainTex"]["m_Texture"]
                texture = None
                if pointer["m_PathID"]:
                    pixels = (
                        importer.pointer(material_obj.assets_file, pointer)
                        .read()
                        .image.convert("RGBA")
                    )
                    digest = hashlib.sha256(pixels.tobytes()).hexdigest()
                    path = "Textures/battle_line_" + digest[:16] + ".png"
                    (importer.output / "Textures").mkdir(exist_ok=True)
                    pixels.save(importer.output / path)
                    texture = {"path": path, "pixel_sha256": digest}
                lines[label] = {
                    "transform": world.sprite_plane(by_go[line_go], 16)["transform"],
                    "anchor_go": poses[anchor]["m_GameObject"]["m_PathID"],
                    "parameters": renderer["m_Parameters"],
                    "sort": [renderer["m_SortingLayer"], renderer["m_SortingOrder"]],
                    "texture": texture,
                    "material": {
                        "name": material["m_Name"],
                        "keywords": material["m_ValidKeywords"],
                        "color": rgba(colors["_Color"]),
                        "glow_color": rgba(colors["_GlowColor"]),
                        "floats": {
                            k: floats[k]
                            for k in ["_Alpha", "_FadeAmount", "_Glow", "_GlowGlobal"]
                            if k in floats
                        },
                    },
                }
            result[go]["rifle_binding"] = lines
    return result, visuals
