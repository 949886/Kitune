"""Export the shipped URP renderer, falloff texture and persistent global lights."""

from __future__ import annotations

import hashlib

import UnityPy
from UnityPy.classes import PPtr


def light_settings(data):
    """Retain source enums; NormalMapQuality.Disabled is 2, not 0."""
    return {
        "blend_style": data["m_BlendStyleIndex"],
        "falloff": data["m_FalloffIntensity"],
        "inner_radius": data["m_PointLightInnerRadius"],
        "inner_angle": data["m_PointLightInnerAngle"],
        "outer_angle": data["m_PointLightOuterAngle"],
        "normal_quality": data["m_NormalMapQuality"],
        "normal_distance": data["m_NormalMapDistance"],
        "overlap": data["m_OverlapOperation"],
        "order": data["m_LightOrder"],
        "shadows": bool(data["m_ShadowIntensityEnabled"]),
    }


def renderer_settings(source, output, generator):
    env = UnityPy.load(str(source / "globalgamemanagers"))
    env.typetree_generator = generator
    graphics = next(obj for obj in env.objects if obj.type.name == "GraphicsSettings")
    pipeline = PPtr(
        **graphics.read_typetree()["m_CustomRenderPipeline"], assetsfile=graphics.assets_file
    ).deref()
    config = pipeline.read_typetree()
    renderer = PPtr(
        **config["m_RendererDataList"][config["m_DefaultRendererIndex"]],
        assetsfile=pipeline.assets_file,
    ).deref()
    data = renderer.read_typetree()

    falloff = PPtr(**data["m_FallOffLookup"], assetsfile=renderer.assets_file).read()
    falloff.image.save(output / "light_falloff.png")

    # BrightVolume has priority 1. VolumeManager.SetBrightness overrides its
    # exposure with (slider + 0.5) * 1.7; GameSettingData defaults slider to 0.5.
    brightness = {
        "default_slider": 0.5,
        "exposure_offset": 0.5,
        "exposure_scale": 1.7,
        "source_method": "VolumeManager.SetBrightness / GameSettingData.ResetVideoSetting",
    }
    return {
        "renderer": data["m_Name"],
        "hdr_emulation_scale": data["m_HDREmulationScale"],
        "blend_styles": data["m_LightBlendStyles"],
        "falloff_texture": "light_falloff.png",
        "global_lights": global_lights(source, generator),
        "brightness": brightness,
        "bloom": bloom_settings(source, generator),
        "source_files": {
            filename: hashlib.sha256((source / filename).read_bytes()).hexdigest()
            for filename in [
                "globalgamemanagers",
                "globalgamemanagers.assets",
                "level1",
                "sharedassets1.assets",
                "Managed/Assembly-CSharp.dll",
                "Managed/Unity.RenderPipelines.Universal.Runtime.dll",
            ]
        },
    }


def bloom_settings(source, generator):
    """Follow the game's normal Volume and honor override flags, not stale values."""
    env = UnityPy.load(str(source / "level1"))
    env.typetree_generator = generator
    manager = next(
        obj
        for obj in env.objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "VolumeManager"
    )
    manager_data = manager.read_typetree()
    volume = PPtr(**manager_data["GlobalVolume"], assetsfile=manager.assets_file).deref()
    volume_data = volume.read_typetree()
    profile = PPtr(**volume_data["sharedProfile"], assetsfile=volume.assets_file).deref()
    profile_data = profile.read_typetree()
    components = [
        PPtr(**pointer, assetsfile=profile.assets_file).deref()
        for pointer in profile_data["components"]
    ]
    bloom = next(
        obj
        for obj in components
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "Bloom"
    )
    data = bloom.read_typetree()

    # Defaults verified from this build's Universal.Runtime Bloom constructor.
    # For example, serialized HQ=true and scatter=.71 have override=false.
    defaults = {
        "threshold": 0.9,
        "intensity": 0.0,
        "scatter": 0.7,
        "clamp": 65472.0,
        "tint": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
        "highQualityFiltering": False,
        "downscale": 0,
        "maxIterations": 6,
        "dirtIntensity": 0.0,
    }
    effective = {
        key: data[key]["m_Value"] if data[key]["m_OverrideState"] else default
        for key, default in defaults.items()
    }
    return {
        "active": bool(data["active"]),
        "profile": profile_data["m_Name"],
        "source_id": bloom.path_id,
        "volume_weight": volume_data["weight"],
        "effective": effective,
        "overrides": {key: bool(data[key]["m_OverrideState"]) for key in defaults},
    }


def global_lights(source, generator):
    env = UnityPy.load(str(source / "level1"))
    env.typetree_generator = generator
    objects = list(env.objects)
    gos = {obj.path_id: obj.read_typetree() for obj in objects if obj.type.name == "GameObject"}
    transforms = {
        obj.path_id: obj.read_typetree() for obj in objects if obj.type.name == "Transform"
    }
    by_go = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}

    def active(go):
        tid = by_go[go]
        while tid:
            transform = transforms[tid]
            if not gos[transform["m_GameObject"]["m_PathID"]]["m_IsActive"]:
                return False
            tid = transform["m_Father"]["m_PathID"]
        return True

    lights = []
    for obj in objects:
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if head.m_Script.read().m_ClassName != "Light2D" or not active(head.m_GameObject.path_id):
            continue

        data = obj.read_typetree()
        if not data["m_Enabled"] or data["m_LightType"] != 4:
            continue
        lights.append(
            {
                "source_id": obj.path_id,
                "color": [data["m_Color"][channel] for channel in "rgba"],
                "energy": data["m_Intensity"],
                "layers": data["m_ApplyToSortingLayers"],
                "blend_style": data["m_BlendStyleIndex"],
            }
        )
    return lights
