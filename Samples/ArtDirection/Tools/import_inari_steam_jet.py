"""Extract the tutorial SteamTrap as a self-contained, movable Godot device.

The authored hierarchy has no damage collider or Fire behaviour. Preserve that
fact; a similarly named unused Fire class is not evidence for adding damage.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from import_inari import Importer, UnityPy, PPtr, dump, rgba
from import_inari_particles import portable
from unity_scene_spatial import WorldTransforms
from unity_scene_animation import target_paths, animator_tracks


def export(source: Path, package: Path, profile: dict):
    output = package / "Assets" / profile["asset_folder"]
    output.mkdir(parents=True, exist_ok=True)
    # Importer emits global camera/lighting helpers at construction; keep those
    # unrelated files in scratch storage, not in this device's distributable.
    scratch = package.parents[1] / "tmp/art-direction/steam-export"
    imp = Importer(source, scratch)
    scene = source / profile["scene"]
    env = UnityPy.load(str(scene))
    env.typetree_generator = imp.generator
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == scene.name}
    gos = {i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"}
    poses = {i: o.read_typetree() for i, o in objects.items() if o.type.name in ("Transform", "RectTransform")}
    by_go = {p["m_GameObject"]["m_PathID"]: i for i, p in poses.items()}
    root = profile["root_go"]
    assert gos[root]["m_Name"] == profile["root_name"]
    paths = target_paths(root, gos, poses, by_go)
    original_root = copy.deepcopy(poses[by_go[root]])
    poses[by_go[root]].update(m_Father={"m_FileID": 0, "m_PathID": 0},
                            m_LocalPosition=dict(x=0, y=0, z=0),
                            m_LocalRotation=dict(x=0, y=0, z=0, w=1),
                            m_LocalScale=dict(x=1, y=1, z=1))
    world = WorldTransforms(poses)
    sprites, emitters, tracks, evidence = [], [], [], []
    hashes = {scene.name: hashlib.sha256(scene.read_bytes()).hexdigest()}

    def track_source(obj):
        name = obj.assets_file.name
        if name not in hashes and (source / name).is_file():
            hashes[name] = hashlib.sha256((source / name).read_bytes()).hexdigest()

    def material(pointer):
        imp.material(pointer)
        obj = pointer.deref()
        track_source(obj)
        track_source(obj.read().m_Shader.deref())
        raw = obj.read_typetree()
        props = raw["m_SavedProperties"]
        result = copy.deepcopy(imp.material_details[raw["m_Name"]])
        result.update(name=raw["m_Name"], floats=dict(props["m_Floats"]),
                      shader=obj.read().m_Shader.read().m_ParsedForm.m_Name)
        return result, raw

    for go_id in paths.values():
        components = {objects[c["component"]["m_PathID"]].type.name:
                      objects[c["component"]["m_PathID"]] for c in gos[go_id]["m_Component"]}
        behaviours = []
        for entry in gos[go_id]["m_Component"]:
            component = objects[entry["component"]["m_PathID"]]
            if component.type.name == "MonoBehaviour":
                behaviours.append(component.parse_monobehaviour_head().m_Script.read().m_ClassName)
        assert "Fire" not in behaviours
        evidence.append({"go": go_id, "name": gos[go_id]["m_Name"], "components": list(components),
                         "behaviours": behaviours})
        assert not any(k.endswith("Collider2D") for k in components)
        if "Animator" in components:
            tracks += animator_tracks(imp, components["Animator"], paths, poses, by_go)
            controller = components["Animator"].read().m_Controller
            track_source(controller.deref())
            for clip in controller.read().m_AnimationClips:
                track_source(clip.deref())
        if "SpriteRenderer" in components:
            renderer = components["SpriteRenderer"].read()
            key = imp.sprite(renderer.m_Sprite)
            if key:
                track_source(renderer.m_Sprite.deref())
                mat, _ = material(renderer.m_Materials[0])
                raw = components["SpriteRenderer"].read_typetree()
                sprites.append({"go": go_id, "sprite": key,
                                "transform": world.sprite_plane(by_go[go_id], 16)["transform"],
                                "color": rgba(raw["m_Color"]), "flip": [raw["m_FlipX"], raw["m_FlipY"]],
                                "sort": [raw["m_SortingLayer"], raw["m_SortingOrder"]], "material": mat})
        if "ParticleSystem" in components:
            system = components["ParticleSystem"].read_typetree()
            assert not system["CollisionModule"]["enabled"] and not system["TriggerModule"]["enabled"]
            renderer_obj = components["ParticleSystemRenderer"]
            renderer = renderer_obj.read_typetree()
            mat, raw = material(renderer_obj.read().m_Materials[0])
            tex_env = dict(raw["m_SavedProperties"]["m_TexEnvs"])["_MainTex"]
            # Texture pointers are relative to the material file, not the scene.
            material_obj = renderer_obj.read().m_Materials[0].deref()
            texture_obj = PPtr(**tex_env["m_Texture"], assetsfile=material_obj.assets_file).deref()
            texture = texture_obj.read()
            track_source(texture_obj)
            pixels = texture.image.convert("RGBA")
            filename = f"particle_{texture_obj.path_id}.png"
            pixels.save(output / filename)
            mat["particle_sampling"] = {"main_texture_st": [tex_env["m_Scale"]["x"], tex_env["m_Scale"]["y"], tex_env["m_Offset"]["x"], tex_env["m_Offset"]["y"]],
                "color_space": texture.m_ColorSpace, "wrap_u": texture.m_TextureSettings.m_WrapU, "wrap_v": texture.m_TextureSettings.m_WrapV}
            emitters.append({"name": gos[go_id]["m_Name"], "transform": world.matrix(by_go[go_id]),
                "system": system, "renderer": renderer, "material": mat,
                "texture": {"path": filename, "filter": texture.m_TextureSettings.m_FilterMode,
                            "width": pixels.width, "height": pixels.height,
                            "pixel_sha256": hashlib.sha256(pixels.tobytes()).hexdigest()}})
    for key, pixels in imp.images.items():
        pixels.save(output / (key + ".png"))
        imp.sprites[key].update(path=key + ".png", region=[0, 0, pixels.width, pixels.height])
    gravity = next(o.read_typetree()["m_Gravity"] for o in UnityPy.load(str(source / "globalgamemanagers")).objects if o.type.name == "Physics2DSettings")
    dump(output / "device.json", portable({"source_scene": scene.name, "source_go": root,
        "source_name": gos[root]["m_Name"], "source_scene_path": profile["scene_path"],
        "source_root": original_root, "source_sha256": hashes,
        "preview_brightness": json.loads((scratch / "lighting.json").read_text(encoding="utf8"))["brightness"],
        "component_evidence": evidence, "has_authored_damage": False,
        "sprites": sprites, "sprite_info": imp.sprites, "emitters": emitters,
        "tracks": tracks, "gravity": gravity}))
    print(profile["asset_folder"], len(sprites), "sprites,", len(emitters), "emitters")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    profiles = json.loads((root / "Samples/ArtDirection/Profiles/portable_steam_jet.json").read_text(encoding="utf8"))
    for profile in profiles:
        export(args.source, root / "Samples/INARIMechanisms", profile)
