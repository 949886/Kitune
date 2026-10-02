extends SceneTree
## Compare rendered alpha against a CPU evaluation of the shipped UV instructions.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")

var noise: Image
var original: Image


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var info := Assets.sprite_info("sharedassets25_222")
	assert(info.effect_mesh.vertices.size() == 8 and info.effect_mesh.triangles.size() == 6)
	var source := Assets.material_info("Mat_JadeDistotion")
	assert(source.uv_effects.noise.color_space == 1)
	assert(source.uv_effects.noise.filter == 1 and source.uv_effects.noise.wrap_u == 0)
	assert(info.effect_mesh.texture.filter == 0 and info.effect_mesh.texture.wrap_u == 1)
	if DisplayServer.get_name() == "headless":
		print("ORIGINAL_UV_PROBE_PASS (source data; GPU checks require a rendering backend)")
		quit()
		return

	var noise_texture: Texture2D = load(Assets.ROOT + source.uv_effects.noise.path)
	var source_texture: Texture2D = load(Assets.ROOT + info.effect_mesh.texture.path)
	noise = noise_texture.get_image()
	original = source_texture.get_image()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != &"gl_compatibility"
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = load(Assets.ROOT + info.effect_mesh.texture.path)
	sprite.centered = false
	sprite.scale = Vector2(4, 4)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = Glow
	sprite.material = material
	var first: Image
	for material_name in ["Mat_JadeDistotion", "Mat_JadeDistotion 1"]:
		source = Assets.material_info(material_name)
		Settings.configure(material, source, viewport.use_hdr_2d)
		# Isolate sampling from color grading. Alpha still comes from the original
		# texture; both effects and the actual production shader remain enabled.
		material.set_shader_parameter("material_tint", Color.WHITE)
		material.set_shader_parameter("glow_enabled", false)
		for time in [0.0, 0.125, 0.5]:
			material.set_shader_parameter("uv_effect_time", time)
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image()
			var mismatches := 0
			var changed := 0
			for y in range(0, 172, 2):
				for x in range(0, 160, 2):
					var uv := Vector2((x + 0.5) / 160.0, 1.0 - (y + 0.5) / 172.0)
					var sample_uv := _source_uv(uv, time, source)
					var texel := Vector2i(
						clampi(int(floor(sample_uv.x * 40)), 0, 39),
						clampi(int(floor((1.0 - sample_uv.y) * 43)), 0, 42)
					)
					var expected := original.get_pixelv(texel).a
					if absf(actual.get_pixel(x, y).a - expected) > 0.02:
						mismatches += 1
					if (
						first != null
						and absf(actual.get_pixel(x, y).a - first.get_pixel(x, y).a) > 0.02
					):
						changed += 1
			print(
				"UV_GPU ",
				material_name,
				" t=",
				time,
				" mismatches=",
				mismatches,
				" changed=",
				changed
			)
			assert(mismatches <= 8, "GPU UV sampling disagrees with the source instruction oracle")
			if first == null:
				first = actual
			elif time > 0.0:
				assert(changed > 20, "Source deformation must change over time")
	viewport.queue_free()
	await process_frame
	print("ORIGINAL_UV_PROBE_PASS")
	quit()


func _source_uv(uv: Vector2, time: float, source: Dictionary) -> Vector2:
	var parameters: Dictionary = source.uv_effects.parameters
	var start := uv
	var scroll := Vector2(parameters._DistortTexXSpeed, parameters._DistortTexYSpeed) * time / 20.0
	var displacement := (_noise(uv + scroll) - 0.5) * 0.2 * float(parameters._DistortAmount)
	uv += Vector2.ONE * displacement
	var delta := Vector2(parameters._WaveX, parameters._WaveY) - uv
	delta = Vector2(fmod(delta.x, 1.0), fmod(delta.y, 1.0))
	delta.x *= 320.0 / 180.0
	uv += (
		delta
		* sin(delta.length() * float(parameters._WaveAmount) - time * float(parameters._WaveSpeed))
		* float(parameters._WaveStrength)
		/ 1000.0
	)
	if "ROUNDWAVEUV_ON" in source.keywords:
		var distance := (Vector2.ONE * 0.5 - start) * Vector2(1.0, 43.0 / 40.0)
		uv += (
			Vector2.ONE
			* sin((time * float(parameters._RoundWaveSpeed) / 10.0 - distance.length()) * 66.666672)
			* float(parameters._RoundWaveStrength)
			/ 10.0
		)
	return uv


func _noise(uv: Vector2) -> float:
	var point := Vector2(uv.x, 1.0 - uv.y) * Vector2(noise.get_size()) - Vector2.ONE * 0.5
	var base := Vector2i(point.floor())
	var weight := point - point.floor()
	var top := lerpf(_noise_pixel(base), _noise_pixel(base + Vector2i.RIGHT), weight.x)
	var bottom := lerpf(
		_noise_pixel(base + Vector2i.DOWN), _noise_pixel(base + Vector2i.ONE), weight.x
	)
	return lerpf(top, bottom, weight.y)


func _noise_pixel(point: Vector2i) -> float:
	point.x = posmod(point.x, noise.get_width())
	point.y = posmod(point.y, noise.get_height())
	return noise.get_pixelv(point).srgb_to_linear().r
