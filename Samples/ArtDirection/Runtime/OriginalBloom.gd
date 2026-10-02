extends Node
## Source URP Gaussian pyramid. Every pass reads HDR linear scene values.

const FilterShader = preload("res://Samples/ArtDirection/Shaders/OriginalBloom.gdshader")
const CompositeShader = preload("res://Samples/ArtDirection/Shaders/OriginalBloomComposite.gdshader")

enum Pass { PREFILTER, HORIZONTAL, VERTICAL, UPSAMPLE }

var presentation := ShaderMaterial.new()
var passes: Array[SubViewport] = []
var mip_sizes: Array[Vector2i] = []
var outermost: SubViewport
var tuning: Dictionary


func configure(
	source: SubViewport, settings: Dictionary, destination: Viewport, exposure: float
) -> void:
	assert(source.use_hdr_2d, "Bloom needs an unclipped linear scene buffer")
	tuning = settings.effective
	assert(not tuning.highQualityFiltering and is_zero_approx(tuning.dirtIntensity))
	assert(is_equal_approx(settings.volume_weight, 1.0))
	outermost = source

	var divisor := 2 if int(tuning.downscale) == 0 else 4
	var size := Vector2i(source.size.x / divisor, source.size.y / divisor)
	# Integer log2 avoids losing an iteration at exact powers of two due to
	# floating-point log division (e.g. 32 can evaluate just below 2^5).
	var iterations := 0
	var remaining := maxi(size.x, size.y)
	while remaining >= 4:
		iterations += 1
		remaining /= 2
	var count := clampi(iterations, 1, int(tuning.maxIterations))
	var down: Array[SubViewport] = []
	down.append(_make_pass(Pass.PREFILTER, size, source.get_texture()))
	mip_sizes.append(size)

	for index in range(1, count):
		size = Vector2i(maxi(1, size.x / 2), maxi(1, size.y / 2))
		var horizontal := _make_pass(Pass.HORIZONTAL, size, down.back().get_texture())
		down.append(_make_pass(Pass.VERTICAL, size, horizontal.get_texture()))
		mip_sizes.append(size)

	var low: SubViewport = down.back()
	for index in range(count - 2, -1, -1):
		low = _make_pass(
			Pass.UPSAMPLE, mip_sizes[index], down[index].get_texture(), low.get_texture()
		)

	# Bloom is added before the source post-exposure and final color encoding.
	presentation.shader = CompositeShader
	presentation.set_shader_parameter("chromatic_source", source.get_texture())
	presentation.set_shader_parameter("bloom_texture", low.get_texture())
	presentation.set_shader_parameter("intensity", tuning.intensity)
	presentation.set_shader_parameter("exposure_stops", exposure)
	presentation.set_shader_parameter("linear_destination", destination.use_hdr_2d)
	var color: Dictionary = tuning.tint
	var tint := Color(color.r, color.g, color.b).srgb_to_linear()
	var luminance := tint.r * 0.2126729 + tint.g * 0.7151522 + tint.b * 0.0721750
	var normalized := (
		Vector3(tint.r, tint.g, tint.b) / luminance if luminance > 0.0 else Vector3.ONE
	)
	presentation.set_shader_parameter("bloom_tint", normalized)


func _make_pass(
	mode: Pass, size: Vector2i, texture: Texture2D, low: Texture2D = null
) -> SubViewport:
	var target := SubViewport.new()
	target.name = "BloomPass%d" % passes.size()
	target.size = size
	target.use_hdr_2d = true
	target.world_2d = World2D.new()
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(target)

	# Godot renders child viewports before their parents. Nest the whole previous
	# chain, including the scene, so animated highlights cannot trail by a frame.
	outermost.reparent(target)
	outermost = target
	passes.append(target)

	var filter := ShaderMaterial.new()
	filter.shader = FilterShader
	filter.set_shader_parameter("source_texture", texture)
	filter.set_shader_parameter("pass_mode", mode)
	filter.set_shader_parameter("scatter", lerpf(0.05, 0.95, tuning.scatter))
	filter.set_shader_parameter("clamp_max", tuning.clamp)
	var threshold := float(tuning.threshold)
	filter.set_shader_parameter(
		"threshold", Color(threshold, threshold, threshold).srgb_to_linear().r
	)
	if low != null:
		filter.set_shader_parameter("low_texture", low)
	var quad := ColorRect.new()
	quad.size = Vector2(size)
	quad.material = filter
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(quad)
	return target
