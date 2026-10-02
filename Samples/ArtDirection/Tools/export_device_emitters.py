"""Export authored child particle systems of a portable device by source IDs.

Reads the device's existing provenance/animation hierarchy; no duplicated level
coordinates or guessed effect parameters. Sprite/logic export runs first.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
from import_inari import Importer, UnityPy, PPtr, dump
from import_inari_particles import portable
from unity_scene_spatial import WorldTransforms


def export(source: Path, kind: str):
    root = Path(__file__).resolve().parents[3]
    output = root / "Samples/INARIMechanisms/Assets" / kind
    device = json.loads((output / "device.json").read_text(encoding="utf8"))
    imp = Importer(source, root / "tmp/art-direction/device-emitter-export" / kind)
    scene = source / device["source_scene"]
    env = UnityPy.load(str(scene))
    objects = {o.path_id: o for o in env.objects if o.assets_file.name == scene.name}
    gos = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "GameObject"
    }
    poses = {
        i: o.read_typetree() for i, o in objects.items() if o.type.name == "Transform"
    }
    by_go = {p["m_GameObject"]["m_PathID"]: i for i, p in poses.items()}
    origin = device["record"].get("particle_origin_world_pixels")
    if origin is None:
        poses[by_go[int(device["record"]["go"])]].update(
            m_Father={"m_FileID": 0, "m_PathID": 0},
            m_LocalPosition=dict(x=0, y=0, z=0),
            m_LocalRotation=dict(x=0, y=0, z=0, w=1),
            m_LocalScale=dict(x=1, y=1, z=1),
        )
    world = WorldTransforms(poses)
    emitters = []
    inactive_renderers = []
    hashes = {scene.name: hashlib.sha256(scene.read_bytes()).hexdigest()}
    for go_id in device["record"]["animation"]["children"]:
        components = {
            objects[c["component"]["m_PathID"]].type.name: objects[
                c["component"]["m_PathID"]
            ]
            for c in gos[go_id]["m_Component"]
        }
        if "ParticleSystem" not in components:
            continue
        system = components["ParticleSystem"].read_typetree()
        assert not system["TriggerModule"]["enabled"]
        collision = system["CollisionModule"]
        if collision["enabled"]:
            # The existing runtime supports world-space 2D surface bounces.
            # Forces and script collision messages require a separate host API.
            assert collision["type"] == 1 and collision["collisionMode"] == 1
            assert (
                collision["colliderForce"] == 0 and not collision["collisionMessages"]
            )
        renderer_obj = components["ParticleSystemRenderer"]
        if not renderer_obj.read_typetree()["m_Enabled"]:
            # Arrival prefabs contain non-rendering particle parent groups.
            # They carry hierarchy activation, but emit no particles or child
            # sub-emitter events. Keep evidence rather than dereferencing their
            # deliberately null material as a visible effect.
            assert not system["EmissionModule"]["enabled"] and not system["SubModule"]["enabled"]
            inactive_renderers.append(dict(go=go_id, system=system, renderer=renderer_obj.read_typetree()))
            continue
        material_ptr = renderer_obj.read().m_Materials[0]
        imp.material(material_ptr)
        material_obj = material_ptr.deref()
        raw = material_obj.read_typetree()
        props = raw["m_SavedProperties"]
        mat = copy.deepcopy(imp.material_details[raw["m_Name"]])
        mat.update(
            name=raw["m_Name"],
            floats=dict(props["m_Floats"]),
            shader=material_obj.read().m_Shader.read().m_ParsedForm.m_Name,
        )
        tex_env = dict(props["m_TexEnvs"])["_MainTex"]
        texture_obj = PPtr(
            **tex_env["m_Texture"], assetsfile=material_obj.assets_file
        ).deref()
        for obj in [material_obj, texture_obj, material_obj.read().m_Shader.deref()]:
            name = obj.assets_file.name
            if name not in hashes and (source / name).is_file():
                hashes[name] = hashlib.sha256((source / name).read_bytes()).hexdigest()
        texture = texture_obj.read()
        pixels = texture.image.convert("RGBA")
        filename = f"ambient_{texture_obj.path_id}.png"
        pixels.save(output / filename)
        mat["particle_sampling"] = {
            "main_texture_st": [
                tex_env["m_Scale"]["x"],
                tex_env["m_Scale"]["y"],
                tex_env["m_Offset"]["x"],
                tex_env["m_Offset"]["y"],
            ],
            "color_space": texture.m_ColorSpace,
            "wrap_u": texture.m_TextureSettings.m_WrapU,
            "wrap_v": texture.m_TextureSettings.m_WrapV,
        }
        pose = world.matrix(by_go[go_id])
        if origin is not None:
            pose[0][3] -= origin[0] / 16.0
            pose[1][3] += origin[1] / 16.0
        ancestors = []
        cursor = poses[by_go[go_id]]["m_Father"]["m_PathID"]
        while cursor:
            ancestors.append(poses[cursor]["m_GameObject"]["m_PathID"])
            cursor = poses[cursor]["m_Father"]["m_PathID"]
        emitters.append(
            dict(
                go=go_id,
                active=gos[go_id]["m_IsActive"] and all(gos[i]["m_IsActive"] for i in ancestors),
                ancestor_gos=ancestors,
                name=gos[go_id]["m_Name"],
                transform=pose,
                system=system,
                renderer=renderer_obj.read_typetree(),
                material=mat,
                texture=dict(
                    path=filename,
                    filter=texture.m_TextureSettings.m_FilterMode,
                    width=pixels.width,
                    height=pixels.height,
                    pixel_sha256=hashlib.sha256(pixels.tobytes()).hexdigest(),
                ),
            )
        )
    dump(
        output / "ambient.json", portable(dict(emitters=emitters, source_sha256=hashes, inactive_renderers=inactive_renderers))
    )
    print(kind, "authored particle systems:", len(emitters))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("kind")
    args = parser.parse_args()
    export(args.source, args.kind)
