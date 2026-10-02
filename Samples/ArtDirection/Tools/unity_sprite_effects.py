"""Preserve source UV effects and tight meshes without re-atlasing their UV domain."""

from UnityPy.helpers.MeshHelper import MeshHandler

UV_KEYWORDS = {"DISTORT_ON", "WAVEUV_ON", "ROUNDWAVEUV_ON", "WARP_ON", "WIND_ON"}


def material_effects(importer, material, data):
    keywords = set(data.get("m_ValidKeywords", []))
    # More complex combinations have additional stages whose order is not ported.
    warp_only = keywords == {"WARP_ON", "GLOWLIGHT_ON"}
    if not warp_only and (
        "WARP_ON" in keywords
        or not keywords & UV_KEYWORDS
        # OUTDIST/8DIR alone do not enable an outline. The shipped factory
        # programs contain only distortion/wave sampling when OUTBASE is absent.
        or keywords - (UV_KEYWORDS | {"GLOW_ON", "OUTDIST_ON", "OUTBASE8DIR_ON"})
    ):
        return None
    saved = data["m_SavedProperties"]
    floats = dict(saved["m_Floats"])
    textures = dict(saved["m_TexEnvs"])
    result = {
        "parameters": {
            key: floats[key]
            for key in (
                "_DistortAmount",
                "_DistortTexXSpeed",
                "_DistortTexYSpeed",
                "_WaveAmount",
                "_WaveSpeed",
                "_WaveStrength",
                "_WaveX",
                "_WaveY",
                "_RoundWaveSpeed",
                "_RoundWaveStrength",
                "_WarpScale",
                "_WarpSpeed",
                "_WarpStrength",
            )
        }
    }
    if "WIND_ON" in keywords:
        assert floats["_GrassManualToggle"] == 0.0
        result["parameters"].update(
            {key: floats[key] for key in ("_GrassSpeed", "_GrassWind", "_GrassRadialBend")}
        )
    for name in ("_MainTex", "_DistortTex"):
        texture = textures[name]
        result[name + "_ST"] = [
            texture["m_Scale"]["x"],
            texture["m_Scale"]["y"],
            texture["m_Offset"]["x"],
            texture["m_Offset"]["y"],
        ]
    if "DISTORT_ON" in keywords:
        result["noise"] = importer.texture_asset(
            importer.pointer(material.assets_file, textures["_DistortTex"]["m_Texture"])
        )
        noise = result["noise"]
        if (
            noise["filter"] != 1
            or noise["wrap_u"] != 0
            or noise["wrap_v"] != 0
            or noise["mip_count"] != 1
        ):
            raise ValueError(
                "UV noise sampler requires the source bilinear repeat texture without mips"
            )
    return result


def sprite_effect_mesh(importer, sprite, pixels_per_unit):
    render_data = sprite.m_RD
    if sprite.m_SpriteAtlas:
        render_data = next(
            value
            for key, value in sprite.m_SpriteAtlas.read().m_RenderDataMap
            if key == sprite.m_RenderDataKey
        )
        if render_data.alphaTexture or render_data.downscaleMultiplier != 1.0:
            raise ValueError("Separate alpha and downscaled sprite atlases are not supported")
    if (render_data.settingsRaw >> 2) & 15:
        raise ValueError("Rotated source atlas meshes require a separate UV transform")
    mesh = MeshHandler(sprite.m_RD, sprite.object_reader.version)
    mesh.process()
    texture = importer.texture_asset(render_data.texture)
    if (
        texture["filter"] not in (0, 1)
        or texture["wrap_u"] != 1
        or texture["wrap_v"] != 1
        or texture["mip_count"] != 1
    ):
        raise ValueError("UV sprite sampler requires a nearest/linear clamp texture without mips")
    transform = render_data.uvTransform
    uvs = mesh.m_UV0
    if not uvs or not any(u or v for u, v in uvs):
        uvs = [
            (
                (x * transform.x + transform.y) / texture["width"],
                (y * transform.z + transform.w) / texture["height"],
            )
            for x, y, z in mesh.m_Vertices
        ]
    return {
        "texture": texture,
        "vertices": [[x * pixels_per_unit, -y * pixels_per_unit] for x, y, z in mesh.m_Vertices],
        "uv": [[u, 1.0 - v] for u, v in uvs],
        "triangles": [list(triangle) for submesh in mesh.get_triangles() for triangle in submesh],
    }
