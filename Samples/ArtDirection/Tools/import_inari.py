"""Read original Unity scenes into a portable Godot visual-study data set.

Read-only input. No game executable is run and no source asset is modified.
Dependencies: UnityPy==1.25.3, Pillow==12.3.0, TypeTreeGeneratorAPI==0.0.10.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import sys
import struct

# Optional workspace-local dependencies; a normal virtual environment also works.
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tmp/art-direction/pydeps"))
import UnityPy
from UnityPy.classes import PPtr
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator
from PIL import Image
from unity_scene_animation import collect_tracks
from unity_scene_spatial import SceneSpatial, gameplay_camera
from unity_scene_lighting import light_settings, renderer_settings
from unity_scene_enemies import collect_enemies, collect_navigation, runtime_navigation_grid
from unity_sprite_effects import material_effects, sprite_effect_mesh
from unity_enemy_combat import ranged_visuals

PIXELS_PER_UNIT = 16
ATLAS_SIZE = 4096


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf8")
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(content)
    publish_file(temporary, path)


def publish_file(temporary, destination):
    """An open Godot editor must never see a half-written JSON file or PNG."""
    if destination.exists() and temporary.read_bytes() == destination.read_bytes():
        temporary.unlink()
    else:
        temporary.replace(destination)


def save_atlas(atlas, path):
    temporary = path.with_suffix(path.suffix + ".tmp")
    atlas.save(temporary, format="PNG")
    publish_file(temporary, path)


def rgba(c):
    return [c.get(k, 1) for k in ("r", "g", "b", "a")]


def multiply(a, b):
    return [
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
    ]


class Importer:
    def __init__(self, source, output):
        self.source, self.output = source, output
        self.generator = TypeTreeGenerator("2022.3.62f3")
        self.generator.load_local_game(str(source.parent))
        self.navigation_grid = runtime_navigation_grid(self)
        self.navigation_source_files = {"level1"}
        dump(output / "camera.json", gameplay_camera(source, self.generator))
        dump(output / "lighting.json", renderer_settings(source, output, self.generator))
        self.sprites, self.images, self.materials = {}, {}, {}
        self.material_details = {}
        self.texture_assets = {}
        self.imported_scenes = []
        self.layer_names = []
        for obj in UnityPy.load(str(source / "globalgamemanagers")).objects:
            if obj.type.name == "TagManager":
                self.layer_names = obj.read_typetree()["layers"]

    def pointer(self, file, value):
        return PPtr(**value, assetsfile=file)

    def texture_asset(self, pointer):
        obj = pointer.deref()
        key = f"{Path(obj.assets_file.name).stem}_{obj.path_id}"
        if key not in self.texture_assets:
            texture = obj.read()
            pixels = texture.image.convert("RGBA")
            relative = f"Textures/{key}.png"
            path = self.output / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            save_atlas(pixels, path)
            self.texture_assets[key] = {
                "path": relative,
                "width": pixels.width,
                "height": pixels.height,
                "color_space": texture.m_ColorSpace,
                "mip_count": texture.m_MipCount,
                "filter": texture.m_TextureSettings.m_FilterMode,
                "wrap_u": texture.m_TextureSettings.m_WrapU,
                "wrap_v": texture.m_TextureSettings.m_WrapV,
                "pixel_sha256": hashlib.sha256(pixels.tobytes()).hexdigest(),
                "source_file": obj.assets_file.name,
                "source_id": obj.path_id,
            }
        return self.texture_assets[key]

    def sprite(self, pointer):
        if not pointer:
            return None
        obj = pointer.deref()
        key = f"{Path(obj.assets_file.name).stem}_{obj.path_id}"
        if key in self.sprites:
            return key
        spr = obj.read()
        if not spr.m_RD.texture and not spr.m_SpriteAtlas:
            # Unity also serializes empty collision-only tile sprites.
            return None
        image = spr.image.convert("RGBA")
        offset = spr.m_RD.textureRectOffset
        # Unity pivots are measured up from the bottom; Godot is measured down.
        self.sprites[key] = dict(
            name=spr.m_Name,
            ppu=spr.m_PixelsToUnits,
            size=list(image.size),
            offset=[
                offset.x - spr.m_Pivot.x * spr.m_Rect.width,
                spr.m_Pivot.y * spr.m_Rect.height - offset.y - image.height,
            ],
        )
        self.images[key] = image
        return key

    def material(self, pointer):
        if not pointer:
            return "normal"
        obj = pointer.deref()
        key = (obj.assets_file.name, obj.path_id)
        if key not in self.materials:
            d = obj.read_typetree()
            name = d["m_Name"]
            self.materials[key] = (
                "add" if any(x in name.lower() for x in ["additive", "add "]) else "normal"
            )
            saved = d["m_SavedProperties"]
            floats = dict(saved["m_Floats"])
            colors = dict(saved["m_Colors"])
            # A black glow mask disables emission even when GLOW_ON is enabled.
            # Ignoring this shipped mask turns normal enemies into bright silhouettes.
            textures = dict(saved["m_TexEnvs"])
            glow_texture = textures.get("_GlowTex", {}).get("m_Texture")
            black_glow_mask = False
            if glow_texture and glow_texture["m_PathID"]:
                mask = self.pointer(obj.assets_file, glow_texture).read().image.convert("RGB")
                black_glow_mask = all(channel[1] == 0 for channel in mask.getextrema())
            lighting_mask = [1.0, 1.0, 1.0]
            mask_pointer = textures.get("_MaskTex", {}).get("m_Texture")
            if mask_pointer and mask_pointer["m_PathID"]:
                mask = self.pointer(obj.assets_file, mask_pointer).read().image.convert("RGB")
                bounds = mask.getextrema()
                lighting_mask = (
                    [low / 255.0 for low, high in bounds]
                    if all(low == high for low, high in bounds)
                    else None
                )
            self.material_details[name] = dict(
                name=name,
                shader=obj.read().m_Shader.read().m_ParsedForm.m_Name,
                keywords=d.get("m_ValidKeywords", []),
                alpha=floats.get("_Alpha", 1),
                color=rgba(colors.get("_Color", {})),
                glow=floats.get("_Glow", 1),
                glow_global=floats.get("_GlowGlobal", 1),
                glow_color=rgba(colors.get("_GlowColor", {})),
                black_glow_mask=black_glow_mask,
                lighting_mask=lighting_mask,
                lit_amount=floats.get("_LitAmount", 1),
                hit_color=rgba(colors.get("_HitEffectColor", {})),
                hit_glow=floats.get("_HitEffectGlow", 1),
                hit_blend=floats.get("_HitEffectBlend", 0),
                water_strength=floats.get("_Strength", 0.003),
                water_speed=floats.get("_Speed", 0.01),
                rotation_speed=floats.get("_RotationSpeed", 0.0),
            )
            effects = material_effects(self, obj, d)
            if effects:
                self.material_details[name]["uv_effects"] = effects
        return self.materials[key]

    def scene(self, number, extra_visuals=None, active_roots=(), *, asset_file=None, root_go=None):
        # A runtime-spawned prefab must be read from its actual asset subtree,
        # not reconstructed by cloning a scene instance with different overrides.
        source_name = asset_file or f"level{number}"
        label = source_name if root_go is None else f"subtree-{source_name}-{root_go}"
        self.imported_scenes.append(source_name)
        env = UnityPy.load(str(self.source / source_name))
        env.typetree_generator = self.generator
        objects = list(env.objects)
        if root_go is not None:
            objects = [o for o in objects if o.assets_file.name == source_name]
            all_objects = {o.path_id: o for o in objects}
            all_gos = {o.path_id: o.read_typetree() for o in objects if o.type.name == "GameObject"}
            all_poses = {o.path_id: o.read_typetree() for o in objects if o.type.name in ["Transform", "RectTransform"]}
            by_root = {p["m_GameObject"]["m_PathID"]: i for i, p in all_poses.items()}
            selected, pending = set(), [by_root[root_go]]
            while pending:
                pose = all_poses[pending.pop()]
                go = pose["m_GameObject"]["m_PathID"]
                selected.add(go)
                selected.update(c["component"]["m_PathID"] for c in all_gos[go]["m_Component"])
                pending.extend(c["m_PathID"] for c in pose["m_Children"])
            # Scene instances retain ancestor transforms/activation/sorting;
            # ancestor artwork and unrelated actors are not part of the prefab.
            parent = all_poses[by_root[root_go]]["m_Father"]["m_PathID"]
            while parent:
                pose = all_poses[parent]
                go = pose["m_GameObject"]["m_PathID"]
                selected.update([go, parent])
                selected.update(c["component"]["m_PathID"] for c in all_gos[go]["m_Component"]
                    if all_objects[c["component"]["m_PathID"]].type.name == "SortingGroup")
                parent = pose["m_Father"]["m_PathID"]
            objects = [o for o in objects if o.path_id in selected]
        gos = {o.path_id: o.read_typetree() for o in objects if o.type.name == "GameObject"}
        transforms = {
            o.path_id: o.read_typetree()
            for o in objects
            if o.type.name in ["Transform", "RectTransform"]
        }
        by_go = {v["m_GameObject"]["m_PathID"]: k for k, v in transforms.items()}
        spatial = SceneSpatial(objects, transforms)
        components = collections.defaultdict(dict)
        for o in objects:
            if o.type.name in [
                "SpriteRenderer",
                "TilemapRenderer",
                "TilemapCollider2D",
                "SortingGroup",
                "Grid",
                "Animator",
            ]:
                d = o.read_typetree()
                components[d["m_GameObject"]["m_PathID"]][o.type.name] = (o, d)
        matrices, active_cache = {}, {}

        def matrix(tid):
            if not tid:
                return [1, 0, 0, 1, 0, 0]
            if tid in matrices:
                return matrices[tid]
            t = transforms[tid]
            q = t["m_LocalRotation"]
            s = t["m_LocalScale"]
            p = t["m_LocalPosition"]
            a = 2 * math.atan2(q["z"], q["w"])
            c = math.cos(a)
            n = math.sin(a)
            local = [
                c * s["x"],
                -n * s["x"],
                n * s["y"],
                c * s["y"],
                p["x"] * PIXELS_PER_UNIT,
                -p["y"] * PIXELS_PER_UNIT,
            ]
            result = multiply(matrix(t["m_Father"]["m_PathID"]), local)
            matrices[tid] = result
            return result

        def active(tid):
            if not tid:
                return True
            if tid not in active_cache:
                t = transforms[tid]
                active_cache[tid] = bool(
                    gos[t["m_GameObject"]["m_PathID"]]["m_IsActive"]
                    or t["m_GameObject"]["m_PathID"] in active_roots
                ) and active(t["m_Father"]["m_PathID"])
            return active_cache[tid]

        def order(go, d):
            result = [d.get("m_SortingLayer", 0), d.get("m_SortingOrder", 0)]
            tid = by_go[go]
            while tid:
                t = transforms[tid]
                group = components[t["m_GameObject"]["m_PathID"]].get("SortingGroup")
                if group and group[1].get("m_Enabled", 1):
                    g = group[1]
                    result = [g["m_SortingLayer"], g["m_SortingOrder"]] + result
                tid = t["m_Father"]["m_PathID"]
            return result

        dynamic_visuals = ranged_visuals(self, objects, gos, transforms, by_go, active)
        dynamic_visuals.update(extra_visuals or ())
        result = dict(
            source=source_name,
            sprites=[],
            tiles=[],
            colliders=[],
            lights=[],
            markers=[],
            animations=[],
        )
        for obj in objects:
            kind = obj.type.name
            if kind not in [
                "SpriteRenderer",
                "Tilemap",
                "BoxCollider2D",
                "PolygonCollider2D",
                "CircleCollider2D",
                "MonoBehaviour",
            ]:
                continue
            if kind == "MonoBehaviour":
                head = obj.parse_monobehaviour_head()
                class_name = head.m_Script.read().m_ClassName
                if class_name not in ["SceneRoot", "Light2D", "InteractiveDoor"]:
                    continue
            d = obj.read_typetree()
            go = d.get("m_GameObject", {}).get("m_PathID", 0)
            if not go or go not in by_go:
                continue
            tid = by_go[go]
            name = gos[go]["m_Name"]
            m = matrix(tid)
            if kind == "MonoBehaviour" and class_name == "SceneRoot":
                result["spawn"] = matrix(d["PlayerSpawnPoint"]["m_PathID"])[4:6]
                continue
            dynamic_visual = kind == "SpriteRenderer" and go in dynamic_visuals
            if (not active(tid) and not dynamic_visual) or not d.get("m_Enabled", True):
                continue

            if kind == "MonoBehaviour" and class_name == "InteractiveDoor":
                pieces = []
                for piece in d["interactiveDoorParticles"]:
                    rigid = self.pointer(obj.assets_file, piece["rigidbody"]).read_typetree()
                    pieces.append(
                        {
                            "go": piece["gameObject"]["m_PathID"],
                            "mass": rigid["m_Mass"],
                            "gravity_scale": rigid["m_GravityScale"],
                            "rigid_body": rigid,
                            "body_transform": matrix(by_go[piece["gameObject"]["m_PathID"]]),
                        }
                    )
                result.setdefault("doors", []).append(
                    {
                        "go": go,
                        "name": name,
                        "interactions": d["InteractableType"],
                        "health": d["MaxHealth"],
                        "invincible": bool(d["IsInvincible"]),
                        "fade_time": d["DestroyTime"],
                        "pieces": pieces,
                    }
                )
                continue
            if kind == "SpriteRenderer":
                spr = self.sprite(self.pointer(obj.assets_file, d["m_Sprite"]))
                if not spr and not dynamic_visual:
                    continue
                if d["m_Materials"]:
                    material_ptr = self.pointer(obj.assets_file, d["m_Materials"][0])
                    self.material(material_ptr)
                    if spr and self.material_details[material_ptr.read().m_Name].get("uv_effects"):
                        self.sprites[spr]["effect_mesh"] = sprite_effect_mesh(
                            self,
                            self.pointer(obj.assets_file, d["m_Sprite"]).read(),
                            PIXELS_PER_UNIT,
                        )
                result["sprites"].append(
                    dict(
                        name=name,
                        go=go,
                        sprite=spr,
                        visible=active(tid),
                        transform=m,
                        spatial=spatial.sprite_plane(tid, PIXELS_PER_UNIT),
                        sort=order(go, d),
                        layer_id=d["m_SortingLayerID"],
                        color=rgba(d["m_Color"]),
                        flip=[d["m_FlipX"], d["m_FlipY"]],
                        mode=d["m_DrawMode"],
                        size=[
                            d["m_Size"]["x"] * PIXELS_PER_UNIT,
                            d["m_Size"]["y"] * PIXELS_PER_UNIT,
                        ],
                        blend=(
                            self.material(self.pointer(obj.assets_file, d["m_Materials"][0]))
                            if d["m_Materials"]
                            else "normal"
                        ),
                        material=(
                            self.pointer(obj.assets_file, d["m_Materials"][0]).read().m_Name
                            if d["m_Materials"]
                            else ""
                        ),
                    )
                )
            elif kind == "Tilemap":
                renderer = components[go].get("TilemapRenderer")
                collider = components[go].get("TilemapCollider2D")
                visible = renderer is not None and renderer[1]["m_Enabled"]
                # Grid collider tiles are merged into horizontal runs by the runtime.
                points = []
                tiles = []
                for pos, tile in d["m_Tiles"]:
                    idx = tile["m_TileSpriteIndex"]
                    if visible and idx < len(d["m_TileSpriteArray"]):
                        spr = self.sprite(
                            self.pointer(obj.assets_file, d["m_TileSpriteArray"][idx]["m_Data"])
                        )
                        if spr:
                            mat = d["m_TileMatrixArray"][tile["m_TileMatrixIndex"]]["m_Data"]
                            col = d["m_TileColorArray"][tile["m_TileColorIndex"]]["m_Data"]
                            tiles.append(
                                [
                                    pos["x"],
                                    pos["y"],
                                    spr,
                                    rgba(col),
                                    [mat["e00"], -mat["e10"], -mat["e01"], mat["e11"]],
                                ]
                            )
                    if collider and collider[1]["m_Enabled"] and (tile["m_AllTileFlags"] & 3):
                        points.append([pos["x"], pos["y"]])
                if tiles:
                    result["tiles"].append(
                        dict(
                            name=name,
                            go=go,
                            transform=m,
                            sort=order(go, renderer[1]),
                            layer_id=renderer[1]["m_SortingLayerID"],
                            color=rgba(d["m_Color"]),
                            anchor=[d["m_TileAnchor"]["x"], d["m_TileAnchor"]["y"]],
                            tiles=tiles,
                        )
                    )
                if points:
                    result["colliders"].append(
                        dict(
                            name=name,
                            go=go,
                            transform=m,
                            kind="grid",
                            cells=points,
                            one_way="platform" in name.lower(),
                            hazard="trap" in name.lower(),
                            layer=self.layer_names[gos[go]["m_Layer"]],
                        )
                    )
            elif kind.endswith("Collider2D"):
                physics_layer = gos[go]["m_Layer"]
                if d.get("m_IsTrigger") or physics_layer not in [
                    0,
                    7,
                    9,
                    10,
                    11,
                    13,
                    17,
                    18,
                    23,
                    27,
                ]:
                    continue
                item = dict(
                    name=name,
                    go=go,
                    transform=m,
                    kind=kind,
                    offset=[
                        d["m_Offset"]["x"] * PIXELS_PER_UNIT,
                        -d["m_Offset"]["y"] * PIXELS_PER_UNIT,
                    ],
                    one_way=d.get("m_UsedByEffector", False),
                    hazard=physics_layer == 23,
                    layer=self.layer_names[physics_layer],
                )
                if kind == "BoxCollider2D":
                    item["size"] = [
                        d["m_Size"]["x"] * PIXELS_PER_UNIT,
                        d["m_Size"]["y"] * PIXELS_PER_UNIT,
                    ]
                elif kind == "CircleCollider2D":
                    item["radius"] = d["m_Radius"] * PIXELS_PER_UNIT
                else:
                    item["paths"] = [
                        [[p["x"] * PIXELS_PER_UNIT, -p["y"] * PIXELS_PER_UNIT] for p in path]
                        for path in d["m_Points"]["m_Paths"]
                    ]
                result["colliders"].append(item)
            elif kind == "MonoBehaviour":
                result["lights"].append(
                    dict(
                        name=name,
                        transform=m,
                        type=d["m_LightType"],
                        color=rgba(d["m_Color"]),
                        energy=d["m_Intensity"],
                        radius=d["m_PointLightOuterRadius"] * PIXELS_PER_UNIT,
                        layers=d["m_ApplyToSortingLayers"],
                        shape=d["m_ShapePath"],
                        spatial=spatial.sprite_plane(tid, PIXELS_PER_UNIT),
                        settings=light_settings(d),
                    )
                )
        result["navigation"] = collect_navigation(self, objects)
        result["enemies"] = collect_enemies(
            self,
            objects,
            gos,
            transforms,
            by_go,
            active,
            spatial,
            {item["go"] for item in result["sprites"]},
            order,
        )
        result["animations"] = collect_tracks(
            self,
            objects,
            gos,
            transforms,
            by_go,
            active,
            {item["go"] for item in result["sprites"]},
        )

        # Useful original landmarks remain inspectable without relying on path IDs in code.
        for go, d in gos.items():
            if any(
                s in d["m_Name"].lower() for s in ["spawn", "savepoint", "exit", "scene", "door"]
            ):
                result["markers"].append(dict(name=d["m_Name"], position=matrix(by_go[go])[4:6]))
        dump(self.output / f"{label}.json", result)
        print(
            f'{label}: {len(result["sprites"])} sprites, {sum(len(t["tiles"]) for t in result["tiles"])} tiles, spawn={result.get("spawn")}'
        )
        return result

    def player(self):
        env = UnityPy.load(str(self.source / "sharedassets1.assets"))
        # State speed is separate from clip sampling rate (e.g. run 1.8x,
        # double jump 2.5x, combo 2x). Preserve both for faithful action timing.
        speeds = {}
        for obj in env.objects:
            if obj.type.name != "AnimatorController" or obj.peek_name() != "Animator_Player":
                continue
            controller = obj.read_typetree()
            animation_clips = controller["m_AnimationClips"]
            for machine in controller["m_Controller"]["m_StateMachineArray"]:
                for entry in machine["data"]["m_StateConstantArray"]:
                    state = entry["data"]
                    for tree in state["m_BlendTreeConstantArray"]:
                        for node in tree["data"]["m_NodeArray"]:
                            index = node["data"]["m_ClipID"]
                            if index < len(animation_clips):
                                pointer = self.pointer(obj.assets_file, animation_clips[index])
                                speeds[pointer.read().m_Name] = state["m_Speed"]
        selected = {
            "Anim_Player_NewIdle": "idle",
            "Anim_Player_NewRun": "run",
            "Anim_Player_NewRunReady": "run_ready",
            "Anim_Player_NewRunBreak": "run_brake",
            "Anim_Player_NewJump": "jump",
            "Anim_Player_NewFallStart": "fall_start",
            "Anim_Player_NewFall": "fall",
            "Anim_Player_NewDoubleJump": "double_jump",
            "Anim_Player_NewDash": "dash",
            "Anim_Player_NewIdleDash": "dash_idle",
            "Anim_Player_NewRunDash": "dash_run",
            "Animation_Player_DashAttackReady": "weak_dash_ready",
            "Anim_Player_DashAttackToIdle": "weak_dash_idle",
            "Anim_Player_DashAttackToFall": "weak_dash_fall",
            "Anim_Player_NewClimb": "climb",
            "Anim_Player_NewClimbCeiling": "climb_ceiling",
            "Anim_Player_NewClimbCorner": "climb_corner",
            "Animation_Player_ClimbUp": "climb_up",
            "Animation_Player_ClimbDown": "climb_down",
            "Animation_Player_NormalAttack": "attack1",
            "Animation_Player_NormalAttack 1": "attack2",
            "Animation_Player_NormalAttack 2": "attack3",
            "Anim_Player_NewJumpAttack": "jump_attack",
            "Animation_Player_Stamina ATK": "heavy_attack",
            "Anim_Player_NewShurikenDash": "teleport",
            "Animation_Player_WallThrow": "wall_throw",
            "Animation_Player_CeilingThrow": "ceiling_throw",
            "Animation_Player_fall-idle": "landing",
            "Animation_Player_Sit": "sit",
            "Animation_Player_SitIdle": "sit_idle",
            "Animation_Player_SitFinish": "sit_finish",
            "Animation_Player_Dead": "dead",
            "Animation_Player_Spawn": "spawn",
        }
        # Directional throw clips are originals, not rotated stand-in animations.
        for pose in ["Stand", "RunFront", "RunBack", "Jump"]:
            for direction in ["", "Up", "Down"]:
                source_name = f"Anim_Player_NewThrow{pose}{direction}"
                if pose == "Jump" and direction == "Up":
                    source_name = "Anim_Player_NewThrowJump Up"
                selected[source_name] = f'throw_{pose.lower()}_{direction.lower() or "level"}'
        clips = {}
        for obj in env.objects:
            if obj.type.name != "AnimationClip" or obj.peek_name() not in selected:
                continue
            d = obj.read_typetree()
            frames = []
            for curve in d["m_PPtrCurves"]:
                if curve["attribute"] != "m_Sprite":
                    continue
                for frame in curve["curve"]:
                    key = self.sprite(self.pointer(obj.assets_file, frame["value"]))
                    if key:
                        frames.append([frame["time"], key])
            if not frames:
                # Release builds store sprite keys in streamed curves, not editor curves.
                mapping = d["m_ClipBindingConstant"]["pptrCurveMapping"]
                stream = d["m_MuscleClip"]["m_Clip"]["data"]["m_StreamedClip"]["data"]
                raw = struct.pack(f"<{len(stream)}I", *stream)
                offset = 0
                while offset + 8 <= len(raw):
                    time, count = struct.unpack_from("<fI", raw, offset)
                    offset += 8
                    for _ in range(count):
                        index, *coeff = struct.unpack_from("<I4f", raw, offset)
                        offset += 20
                        if index == 0 and time < d["m_MuscleClip"]["m_StopTime"]:
                            frame_index = round(coeff[-1])
                            if 0 <= frame_index < len(mapping):
                                key = self.sprite(
                                    self.pointer(obj.assets_file, mapping[frame_index])
                                )
                                if key:
                                    frames.append([max(0, time), key])
            clips[selected[d["m_Name"]]] = dict(
                frames=frames,
                rate=d["m_SampleRate"],
                length=d["m_MuscleClip"]["m_StopTime"],
                speed=speeds.get(d["m_Name"], 1.0),
                loop=selected[d["m_Name"]]
                in [
                    "idle",
                    "run",
                    "fall",
                    "climb",
                    "climb_up",
                    "climb_down",
                    "climb_ceiling",
                    "sit_idle",
                ],
            )
        dump(self.output / "player.json", clips)
        projectile = next(
            o for o in env.objects if o.type.name == "Sprite" and o.peek_name() == "shuriken3"
        )
        dump(
            self.output / "items.json",
            {
                "kunai": self.sprite(
                    PPtr(m_FileID=0, m_PathID=projectile.path_id, assetsfile=projectile.assets_file)
                )
            },
        )
        print("Player clips:", ", ".join(f'{k}={len(v["frames"])}' for k, v in clips.items()))

    def atlases(self, start_page=0):
        atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE))
        page = start_page
        x = y = row = 0
        for key, img in sorted(self.images.items(), key=lambda item: (-item[1].height, item[0])):
            w, h = img.size
            if x + w + 2 > ATLAS_SIZE:
                x = 0
                y += row
                row = 0
            if y + h + 2 > ATLAS_SIZE:
                save_atlas(atlas, self.output / f"atlas_{page}.png")
                page += 1
                x = y = row = 0
                atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE))
            if w > ATLAS_SIZE or h > ATLAS_SIZE:
                raise ValueError(f"Sprite exceeds atlas: {key}")
            atlas.paste(img, (x + 1, y + 1))
            self.sprites[key]["region"] = [x + 1, y + 1, w, h]
            self.sprites[key]["atlas"] = page
            x += w + 2
            row = max(row, h + 2)
        save_atlas(atlas, self.output / f"atlas_{page}.png")
        dump(self.output / "sprites.json", self.sprites)
        dump(self.output / "materials.json", self.material_details)
        dump(
            self.output / "provenance.json",
            dict(
                game="INARI",
                version="v0.2.1",
                unity="2022.3.62f3",
                conversion="Original sprite pixels, transforms, animation states and navigation cells; partial Godot ports of source materials and gameplay are documented in README.md.",
                source_files={
                    n: hashlib.sha256((self.source / n).read_bytes()).hexdigest()
                    for n in sorted(
                        {
                            *self.imported_scenes,
                            "sharedassets1.assets",
                            *self.navigation_source_files,
                        }
                    )
                },
                sprite_count=len(self.sprites),
                atlas_count=page + 1,
            ),
        )
        print(f"Packed {len(self.sprites)} original sprites into {page+1} atlases.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / "Original/INARI"
    )
    parser.add_argument("--scenes", type=int, nargs="+", default=[2, 15, 25])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    importer = Importer(args.data_directory, args.output)
    for scene_number in args.scenes:
        importer.scene(scene_number)
    importer.player()
    importer.atlases()
