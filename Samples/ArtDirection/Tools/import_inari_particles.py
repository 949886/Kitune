"""Read original enemy/projectile pool references, particle modules and texture pixels."""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, rgba
from unity_scene_spatial import WorldTransforms
from extract_inari_uv_programs import extract

EFFECTS = (
    "Eff_Freezing",
    "Eff_RifleMan_Shot",
    "Eff_Enemy_Bullet_Ground",
    "Eff_ArrowDestroy",
    "ArrowFlight",
    "KunaiFlight",
    "Eff_Player_KunaiStick",
    "Eff_Player_KunaiDestroy",
    "Eff_Accel",
    "PlayerAmbientTrail",
    "Eff_Player_Run",
    "Eff_Enemy_BamBoom_Explosion",
    "Eff_Player_DashAttack",
    "Eff_Player_Attack_3",
    "Eff_PlayerThirdStack",
    "Eff_WeaknessExposure_ver1",
    "Eff_WeaknessExposure_ver2",
    "Eff_WeaknessExposure_ver3",
)


def portable(value):
    """Preserve object IDs and Unity's infinite constant-curve tangents in JSON."""
    if isinstance(value, dict):
        return {
            key: str(item) if key == "m_PathID" else portable(item) for key, item in value.items()
        }
    if isinstance(value, list):
        return [portable(item) for item in value]
    if isinstance(value, float) and not math.isfinite(value):
        assert not math.isnan(value), "Unexpected NaN in source particle data"
        return "Infinity" if value > 0 else "-Infinity"
    return value


def export(source, output):
    bundle = next(source.glob("StreamingAssets/aa/StandaloneWindows64/defaultlocalgroup*.bundle"))
    shader_bundle = next(source.glob("StreamingAssets/aa/StandaloneWindows64/shaderassets*.bundle"))
    builtin_bundle = next(
        source.glob("StreamingAssets/aa/StandaloneWindows64/*unitybuiltinshaders*.bundle")
    )
    kunai_assets = source / "sharedassets1.assets"
    player_scene = source / "level1"
    env = UnityPy.load(
        str(bundle), str(shader_bundle), str(builtin_bundle), str(kunai_assets), str(player_scene)
    )
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    result = {
        "bundle": bundle.name,
        "bundle_sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
        "shader_bundle_sha256": hashlib.sha256(shader_bundle.read_bytes()).hexdigest(),
        "kunai_assets_sha256": hashlib.sha256(kunai_assets.read_bytes()).hexdigest(),
        "player_scene_sha256": hashlib.sha256(player_scene.read_bytes()).hexdigest(),
        "effects": {},
    }
    output.mkdir(parents=True, exist_ok=True)
    shader_cache = {}
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        if obj.assets_file.name == kunai_assets.name:
            if obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "ShurikenObject":
                continue
        if obj.assets_file.name == player_scene.name:
            if obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "PlayerStateMachine":
                continue
        data = obj.read_typetree()
        entries = []
        if obj.assets_file.name == player_scene.name:
            trail = PPtr(**data["MoveSpeedBuffTrailEffect"], assetsfile=obj.assets_file)
            entries = [
                (
                    "PlayerAmbientTrail",
                    PPtr(**trail.read_typetree()["m_GameObject"], assetsfile=obj.assets_file),
                )
            ]
        elif obj.assets_file.name == kunai_assets.name:
            # Keep the entire prefab transform chain, including the native 0.4
            # root scale and the opposing X rotations around its particle child.
            entries = [("KunaiFlight", PPtr(**data["m_GameObject"], assetsfile=obj.assets_file))]
        elif "Dic_Effect" in data:
            entries = [
                (key, PPtr(**reference, assetsfile=obj.assets_file))
                for key, reference in zip(data["Dic_Effect"]["keys"], data["Dic_Effect"]["values"])
            ]
        elif "Dic_Projecttile" in data:
            for key, reference in zip(
                data["Dic_Projecttile"]["keys"], data["Dic_Projecttile"]["values"]
            ):
                if key == "Arrow":
                    arrow = PPtr(**reference, assetsfile=obj.assets_file)
                    entries.append(
                        (
                            "ArrowFlight",
                            PPtr(
                                **arrow.read_typetree()["m_GameObject"], assetsfile=arrow.assetsfile
                            ),
                        )
                    )
        for key, root in entries:
            if key not in EFFECTS:
                continue
            pending = [root]
            nodes, transforms = [], {}
            while pending:
                pointer = pending.pop()
                go = pointer.read_typetree()
                components = {}
                for entry in go["m_Component"]:
                    component = PPtr(**entry["component"], assetsfile=pointer.assetsfile).deref()
                    components[component.type.name] = (component, component.read_typetree())
                transform, pose = components["Transform"]
                transforms[transform.path_id] = pose
                for child in pose["m_Children"]:
                    child_pose = PPtr(**child, assetsfile=pointer.assetsfile).read_typetree()
                    pending.append(
                        PPtr(**child_pose["m_GameObject"], assetsfile=pointer.assetsfile)
                    )
                nodes.append((go, transform.path_id, components))
            root_transform = transforms[nodes[0][1]]
            authored_root = copy.deepcopy(root_transform)
            if key == "PlayerAmbientTrail":
                # This live child is anchored to the player, not borrowed from the pool.
                # Its intervening ambient holder is an identity transform in this build.
                parent = PPtr(
                    **root_transform["m_Father"], assetsfile=root.assetsfile
                ).read_typetree()
                assert parent["m_LocalPosition"] == dict(x=0.0, y=0.0, z=0.0)
                assert parent["m_LocalScale"] == dict(x=1.0, y=1.0, z=1.0)
                assert parent["m_LocalRotation"] == dict(x=0.0, y=0.0, z=0.0, w=1.0)
                root_transform["m_Father"] = dict(m_FileID=0, m_PathID=0)
            elif key not in ("ArrowFlight", "KunaiFlight"):
                # StateMachine.CreateEffect replaces all root TRS values when
                # borrowing a pooled effect. Child transforms remain authored.
                root_transform["m_LocalPosition"] = dict(x=0.0, y=0.0, z=0.0)
                root_transform["m_LocalRotation"] = dict(x=0.0, y=0.0, z=0.0, w=1.0)
                root_transform["m_LocalScale"] = dict(x=1.0, y=1.0, z=1.0)
                if key in ("Eff_Player_KunaiStick", "Eff_Player_KunaiDestroy", "Eff_Accel"):
                    # ShurikenObject borrows directly from the pool, retaining
                    # prefab scale; only Stick assigns a new rotation.
                    root_transform["m_LocalScale"] = authored_root["m_LocalScale"]
                    if key in ("Eff_Player_KunaiDestroy", "Eff_Accel"):
                        root_transform["m_LocalRotation"] = authored_root["m_LocalRotation"]
                if key == "Eff_Player_Run":
                    root_transform["m_LocalRotation"] = authored_root["m_LocalRotation"]
            world = WorldTransforms(transforms)
            active_nodes = {tid: go["m_IsActive"] for go, tid, _ in nodes}

            def active(tid):
                return tid == 0 or (
                    active_nodes[tid] and active(transforms[tid]["m_Father"]["m_PathID"])
                )

            emitters = []
            for go, tid, components in nodes:
                if "ParticleSystemRenderer" not in components or not active(tid):
                    continue
                renderer_obj, renderer = components["ParticleSystemRenderer"]
                if not renderer["m_Enabled"]:
                    continue
                material_obj = PPtr(
                    **renderer["m_Materials"][0], assetsfile=renderer_obj.assets_file
                ).deref()
                material = material_obj.read_typetree()
                props = material["m_SavedProperties"]
                floats, colors = dict(props["m_Floats"]), dict(props["m_Colors"])
                name = material["m_Name"]
                if name not in shader_cache:
                    shader = material_obj.read().m_Shader.read()
                    shader_name = shader.m_ParsedForm.m_Name
                    proof = None
                    if (
                        "Urp2dRenderer" in shader_name
                        or "INNEROUTLINE_ON" in material["m_ValidKeywords"]
                    ):
                        bytecode, parameters, proof = extract(
                            shader, set(material["m_ValidKeywords"])
                        )
                        audit = (
                            Path(__file__).resolve().parents[3]
                            / "tmp/art-direction/particle-lighting"
                        )
                        audit.mkdir(parents=True, exist_ok=True)
                        (audit / (name + ".dxbc")).write_bytes(bytecode)
                        (audit / (name + ".params")).write_bytes(parameters)
                    shader_cache[name] = {"shader": shader_name, "shader_proof": proof}
                mask_reference = dict(props["m_TexEnvs"]).get("_MaskTex", {}).get("m_Texture")
                lighting_mask = [1.0, 1.0, 1.0]
                mask_texture = None
                if mask_reference and mask_reference["m_PathID"]:
                    mask_obj = PPtr(**mask_reference, assetsfile=material_obj.assets_file).deref()
                    mask = mask_obj.read()
                    mask_pixels = mask.image.convert("RGBA")
                    bounds = mask_pixels.convert("RGB").getextrema()
                    if all(low == high for low, high in bounds):
                        lighting_mask = [low / 255.0 for low, high in bounds]
                    else:
                        filename = f"mask_{mask_obj.path_id}.png"
                        mask_pixels.save(output / filename)
                        import_path = (output / filename).with_suffix(".png.import")
                        if import_path.exists():
                            options = import_path.read_text(encoding="utf8")
                            import_path.write_text(
                                options.replace(
                                    "process/fix_alpha_border=true",
                                    "process/fix_alpha_border=false",
                                ),
                                encoding="utf8",
                            )
                        mask_texture = {
                            "path": "Particles/" + filename,
                            "color_space": mask.m_ColorSpace,
                            "filter": mask.m_TextureSettings.m_FilterMode,
                            "pixel_sha256": hashlib.sha256(mask_pixels.tobytes()).hexdigest(),
                        }
                textures = dict(props["m_TexEnvs"])
                glow_texture = None
                if "GLOWTEX_ON" in material["m_ValidKeywords"]:
                    glow_reference = textures["_GlowTex"]["m_Texture"]
                    if glow_reference["m_PathID"]:
                        glow_obj = PPtr(
                            **glow_reference, assetsfile=material_obj.assets_file
                        ).deref()
                        glow = glow_obj.read()
                        glow_pixels = glow.image.convert("RGBA")
                        glow_name = f"glow_{glow_obj.path_id}.png"
                        glow_pixels.save(output / glow_name)
                        glow_import = (output / glow_name).with_suffix(".png.import")
                        if glow_import.exists():
                            options = glow_import.read_text(encoding="utf8")
                            glow_import.write_text(
                                options.replace(
                                    "process/fix_alpha_border=true",
                                    "process/fix_alpha_border=false",
                                ),
                                encoding="utf8",
                            )
                        glow_texture = {
                            "path": "Particles/" + glow_name,
                            "pixel_sha256": hashlib.sha256(glow_pixels.tobytes()).hexdigest(),
                            "color_space": glow.m_ColorSpace,
                            "filter": glow.m_TextureSettings.m_FilterMode,
                            "wrap_u": glow.m_TextureSettings.m_WrapU,
                            "wrap_v": glow.m_TextureSettings.m_WrapV,
                        }
                    else:
                        shader_tree = material_obj.read().m_Shader.deref().read_typetree()
                        prop = next(
                            prop
                            for prop in shader_tree["m_ParsedForm"]["m_PropInfo"]["m_Props"]
                            if prop["m_Name"] == "_GlowTex"
                        )
                        default = prop["m_DefTexture"]["m_DefaultName"]
                        assert default == "white", f"Unrecovered source glow default: {default}"
                        glow_texture = {"default": default, "constant": [1.0, 1.0, 1.0, 1.0]}
                texture_property = "_MainTex" if "_MainTex" in textures else "_BaseMap"
                main = textures[texture_property]["m_Texture"]
                texture_obj = PPtr(**main, assetsfile=material_obj.assets_file).deref()
                texture = texture_obj.read()
                pixels = texture.image.convert("RGBA")
                filename = f"{texture_obj.path_id}.png"
                pixels.save(output / filename)
                import_path = (output / filename).with_suffix(".png.import")
                if import_path.exists():
                    text = import_path.read_text(encoding="utf8")
                    import_path.write_text(
                        text.replace(
                            "process/fix_alpha_border=true", "process/fix_alpha_border=false"
                        ),
                        encoding="utf8",
                    )
                emitters.append(
                    {
                        "name": go["m_Name"],
                        "transform": world.matrix(tid),
                        "system": components["ParticleSystem"][1],
                        "renderer": renderer,
                        "texture": {
                            "path": filename,
                            "pixel_sha256": hashlib.sha256(pixels.tobytes()).hexdigest(),
                            "filter": texture.m_TextureSettings.m_FilterMode,
                            "width": pixels.width,
                            "height": pixels.height,
                        },
                        "material": {
                            **shader_cache[name],
                            "lighting_mask": lighting_mask,
                            "lighting_mask_texture": mask_texture,
                            "lit_amount": floats.get("_LitAmount", 1.0),
                            "name": material["m_Name"],
                            "keywords": material["m_ValidKeywords"],
                            "color": rgba(colors.get("_BaseColor", colors.get("_Color", {}))),
                            "alpha": floats.get("_Alpha", 1),
                            "glow_color": rgba(colors.get("_GlowColor", {})),
                            "glow": floats.get("_Glow", 0),
                            "glow_global": floats.get("_GlowGlobal", 1),
                            "floats": floats,
                            **({"glow_texture": glow_texture} if glow_texture else {}),
                            **(
                                {
                                    "particle_sampling": {
                                        "main_texture_st": [
                                            textures[texture_property]["m_Scale"]["x"],
                                            textures[texture_property]["m_Scale"]["y"],
                                            textures[texture_property]["m_Offset"]["x"],
                                            textures[texture_property]["m_Offset"]["y"],
                                        ],
                                        "color_space": texture.m_ColorSpace,
                                        "wrap_u": texture.m_TextureSettings.m_WrapU,
                                        "wrap_v": texture.m_TextureSettings.m_WrapV,
                                    }
                                }
                                if set(material["m_ValidKeywords"])
                                & {"PINCH_ON", "PIXELATE_ON", "BLUR_ON"}
                                else {}
                            ),
                            "particle_color_operation": rgba(
                                colors.get("_BaseColorAddSubDiff", {})
                            ),
                            **(
                                {"inner_outline_color": rgba(colors["_InnerOutlineColor"])}
                                if "INNEROUTLINE_ON" in material["m_ValidKeywords"]
                                else {}
                            ),
                        },
                    }
                )
            result["effects"][key] = {
                "prefab": root.read_typetree()["m_Name"],
                "authored_root": authored_root,
                "emitters": emitters,
            }
    for obj in UnityPy.load(str(source / "globalgamemanagers")).objects:
        if obj.type.name == "Physics2DSettings":
            result["gravity_2d"] = obj.read_typetree()["m_Gravity"]
    assert set(result["effects"]) == set(EFFECTS)
    (output / "effects.json").write_text(
        json.dumps(portable(result), separators=(",", ":"), allow_nan=False) + "\n",
        encoding="utf8",
    )
    print("Imported", [(key, len(value["emitters"])) for key, value in result["effects"].items()])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    args = parser.parse_args()
    export(args.data_directory, Path(__file__).resolve().parents[1] / "Original/INARI/Particles")
