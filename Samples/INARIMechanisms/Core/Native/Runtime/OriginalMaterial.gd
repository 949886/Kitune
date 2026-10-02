extends RefCounted
## Common AllIn1 material parameters, separated from SpriteRenderer vertex tint.

const Assets = preload("OriginalAssets.gd")


static func configure(
	material: ShaderMaterial, source: Dictionary, linear_framebuffer := false
) -> void:
	material.set_shader_parameter("linear_framebuffer", linear_framebuffer)
	material.set_shader_parameter("material_tint", Assets.color(source.color))
	material.set_shader_parameter("material_alpha", source.alpha)
	material.set_shader_parameter("glow_enabled", "GLOW_ON" in source.keywords)
	material.set_shader_parameter("glow_tint", Assets.color(source.glow_color))
	material.set_shader_parameter("glow_global", source.get("glow_global", 1.0))
	# The original enemy's black glow texture masks colored emission only.
	var masked: bool = "GLOWTEX_ON" in source.keywords and source.get("black_glow_mask", false)
	var amount: float = 0.0 if masked else float(source.glow)
	material.set_shader_parameter("glow_amount", amount)
	var emission: Dictionary = source.get("glow_texture", {})
	material.set_shader_parameter("glow_texture_enabled", not emission.is_empty())
	if not emission.is_empty():
		material.set_shader_parameter("glow_texture_constant", emission.has("constant"))
		if emission.has("constant"):
			material.set_shader_parameter("glow_texture_value", Assets.color(emission.constant))
		else:
			assert(emission.color_space == 1 and emission.filter == 1)
			assert(emission.wrap_u == 1 and emission.wrap_v == 1)
			material.set_shader_parameter("glow_texture", load(Assets.ROOT + emission.path))
	material.set_shader_parameter("hit_enabled", "HITEFFECT_ON" in source.keywords)
	material.set_shader_parameter("hit_tint", Assets.color(source.get("hit_color", [1, 1, 1, 1])))
	material.set_shader_parameter("hit_glow", source.get("hit_glow", 1.0))
	material.set_shader_parameter("hit_blend", source.get("hit_blend", 0.0))
	var color_change: Dictionary = source.get("color_change", {})
	material.set_shader_parameter("color_change_enabled", not color_change.is_empty())
	if not color_change.is_empty():
		material.set_shader_parameter("color_change_target", Assets.color(color_change.target))
		material.set_shader_parameter(
			"color_change_new_color", Assets.color(color_change.new_color)
		)
		material.set_shader_parameter("color_change_tolerance", color_change.tolerance)
		material.set_shader_parameter("color_change_luminosity", color_change.luminosity)
	var outline: Dictionary = source.get("base_outline", {})
	material.set_shader_parameter("base_outline_enabled", not outline.is_empty())
	if not outline.is_empty():
		material.set_shader_parameter("base_outline_color", Assets.color(outline.color))
		material.set_shader_parameter("base_outline_alpha", outline.alpha)
		material.set_shader_parameter("base_outline_glow", outline.glow)
		material.set_shader_parameter("base_outline_pixel_width", int(outline.pixel_width))
		material.set_shader_parameter(
			"base_outline_pixel_perfect", outline.get("pixel_perfect", true)
		)
		material.set_shader_parameter("base_outline_width", outline.get("width", 0.0))
	material.set_shader_parameter("inner_outline_enabled", "INNEROUTLINE_ON" in source.keywords)
	if "INNEROUTLINE_ON" in source.keywords:
		material.set_shader_parameter(
			"inner_outline_color", Assets.color(source.inner_outline_color)
		)
		for name in ["Thickness", "Alpha", "Glow"]:
			material.set_shader_parameter(
				"inner_outline_" + name.to_lower(), source.floats["_InnerOutline" + name]
			)
	_configure_uv(material, source)
	_configure_particle_sampling(material, source)


static func _configure_particle_sampling(material: ShaderMaterial, source: Dictionary) -> void:
	var settings: Dictionary = source.get("particle_sampling", {})
	if settings.is_empty():
		return
	var pinch: bool = "PINCH_ON" in source.keywords
	var pixelate: bool = "PIXELATE_ON" in source.keywords
	var blur: bool = "BLUR_ON" in source.keywords
	assert(settings.wrap_u == 1 and settings.wrap_v == 1)
	assert(settings.color_space == 1)
	material.set_shader_parameter("pinch_enabled", pinch)
	material.set_shader_parameter("pixelate_enabled", pixelate)
	material.set_shader_parameter("particle_blur_enabled", blur)
	if pinch or pixelate:
		material.set_shader_parameter("uv_effects_enabled", true)
		var st: Array = settings.main_texture_st
		material.set_shader_parameter("main_texture_st", Vector4(st[0], st[1], st[2], st[3]))
	if pinch:
		material.set_shader_parameter("pinch_amount", source.floats._PinchUvAmount)
	if pixelate:
		material.set_shader_parameter("pixelate_size", source.floats._PixelateSize)
	if blur:
		assert("BLURISHD_ON" in source.keywords, "Only the shipped HD blur variant is recovered")
		material.set_shader_parameter("particle_blur_intensity", source.floats._BlurIntensity)


static func _configure_uv(material: ShaderMaterial, source: Dictionary) -> void:
	var effects: Dictionary = source.get("uv_effects", {})
	material.set_shader_parameter("uv_effects_enabled", not effects.is_empty())
	if effects.is_empty():
		return
	for entry in [
		["DISTORT_ON", "distort_enabled"],
		["WAVEUV_ON", "wave_enabled"],
		["ROUNDWAVEUV_ON", "round_wave_enabled"],
		["WARP_ON", "warp_enabled"],
		["WIND_ON", "wind_enabled"]
	]:
		material.set_shader_parameter(entry[1], entry[0] in source.keywords)
	var parameters: Dictionary = effects.parameters
	if "WIND_ON" in source.keywords:
		material.set_shader_parameter("grass_speed", parameters._GrassSpeed)
		material.set_shader_parameter("grass_wind", parameters._GrassWind)
		material.set_shader_parameter("grass_radial_bend", parameters._GrassRadialBend)
	var names := {
		"distort_amount": "_DistortAmount",
		"wave_amount": "_WaveAmount",
		"wave_speed": "_WaveSpeed",
		"wave_strength": "_WaveStrength",
		"round_wave_speed": "_RoundWaveSpeed",
		"round_wave_strength": "_RoundWaveStrength",
	}
	for uniform_name in names:
		material.set_shader_parameter(uniform_name, parameters[names[uniform_name]])
	if "WARP_ON" in source.keywords:
		material.set_shader_parameter("warp_scale", parameters._WarpScale)
		material.set_shader_parameter("warp_speed", parameters._WarpSpeed)
		material.set_shader_parameter("warp_strength", parameters._WarpStrength)
	material.set_shader_parameter("wave_center", Vector2(parameters._WaveX, parameters._WaveY))
	material.set_shader_parameter(
		"distort_speed", Vector2(parameters._DistortTexXSpeed, parameters._DistortTexYSpeed)
	)
	for pair in [["_MainTex_ST", "main_texture_st"], ["_DistortTex_ST", "distort_texture_st"]]:
		var st: Array = effects[pair[0]]
		material.set_shader_parameter(pair[1], Vector4(st[0], st[1], st[2], st[3]))
	if effects.has("noise"):
		material.set_shader_parameter("distort_texture", load(Assets.ROOT + effects.noise.path))
		material.set_shader_parameter("distort_srgb", int(effects.noise.color_space) == 1)
