extends SceneTree
## Native coroutine polling, unclamped overrides and an independent GPU RGB oracle.

const Chromatic = preload("res://Samples/ArtDirection/Runtime/InariChromatic.gd")
const Composite = preload("res://Samples/ArtDirection/Shaders/OriginalBloomComposite.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var effect := Chromatic.new()
	root.add_child(effect)
	effect.set_process(false)
	assert(effect.settings.volume_weight == 1.0 and effect.settings.initial_intensity == 0.0)
	var material := ShaderMaterial.new()
	material.shader = Composite
	effect.bind_material(material)
	for index in 3:
		effect.trigger(index, 1.0 / 60.0)
		assert(effect.intensity == effect.settings.intensity[index])
		assert(
			is_equal_approx(
				material.get_shader_parameter("chromatic_amount"), [0.05, 0.075, 0.0875][index]
			)
		)
		var expected_time: float = PackedFloat32Array([1.0 / 60.0])[0]
		var iterations := 1
		while expected_time < float(effect.settings.duration[index]):
			var previous: float = effect.jobs[0].elapsed
			effect.advance(1.0 / 60.0)
			assert(effect.jobs[0].elapsed == previous, "First keepWaiting poll must hold")
			effect.advance(1.0 / 60.0)
			expected_time = PackedFloat32Array(
				[expected_time + PackedFloat32Array([1.0 / 60.0])[0]]
			)[0]
			assert(effect.jobs[0].elapsed == expected_time)
			iterations += 1
		effect.advance(1.0 / 60.0)
		assert(effect.intensity > 0.0)
		effect.advance(1.0 / 60.0)
		assert(effect.jobs.is_empty() and effect.intensity == 0.0)
		print("CHROMATIC_TIMING index=", index, " iterations=", iterations)
	# Native MonoBehaviour coroutines coexist and write the shared volume in
	# insertion order; do not turn repeated hits into an extended single timer.
	effect.trigger(0, 1.0)
	effect.trigger(2, 0.01)
	effect.advance(0.01)
	effect.advance(0.01)
	assert(effect.jobs.size() == 1 and effect.intensity == 1.75)
	if DisplayServer.get_name() != "headless":
		await compare_gpu()
	await check_stage_clock()
	effect.queue_free()
	await process_frame
	print("CHROMATIC_PASS")
	quit()


func sample(pixels: Image, uv: Vector2) -> Color:
	var point := uv * Vector2(pixels.get_size()) - Vector2(0.5, 0.5)
	var low := Vector2i(floori(point.x), floori(point.y))
	var weight := point - Vector2(low)
	var bound := pixels.get_size() - Vector2i.ONE
	var a := pixels.get_pixelv(low.clamp(Vector2i.ZERO, bound))
	var b := pixels.get_pixelv((low + Vector2i.RIGHT).clamp(Vector2i.ZERO, bound))
	var c := pixels.get_pixelv((low + Vector2i.DOWN).clamp(Vector2i.ZERO, bound))
	var d := pixels.get_pixelv((low + Vector2i.ONE).clamp(Vector2i.ZERO, bound))
	return a.lerp(b, weight.x).lerp(c.lerp(d, weight.x), weight.y)


func compare_gpu() -> void:
	var size := Vector2i(64, 48)
	var scene := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	var bloom := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	for y in size.y:
		for x in size.x:
			var u := (x + 0.5) / size.x
			var v := (y + 0.5) / size.y
			scene.set_pixel(x, y, Color(0.1 + u * 2.0, v * 2.0, u * v * 3.0, 1))
			bloom.set_pixel(x, y, Color(v, u * v, u, 1))
	var target := SubViewport.new()
	target.size = size
	target.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var rect := TextureRect.new()
	rect.size = Vector2(size)
	rect.texture = ImageTexture.create_from_image(scene)
	var material := ShaderMaterial.new()
	material.shader = Composite
	material.set_shader_parameter("chromatic_source", rect.texture)
	material.set_shader_parameter("bloom_texture", ImageTexture.create_from_image(bloom))
	material.set_shader_parameter("linear_destination", true)
	material.set_shader_parameter("intensity", 0.2)
	rect.material = material
	target.add_child(rect)
	# HDR oracle avoids clipping. Compatibility exercises the actual gameplay
	# fallback separately in WeakDashProbe, since its framebuffer is bounded.
	if not target.use_hdr_2d:
		target.queue_free()
		return
	for amount: float in [0.0, 0.05, 0.075, 0.0875]:
		material.set_shader_parameter("chromatic_amount", amount)
		await process_frame
		await RenderingServer.frame_post_draw
		var actual := target.get_texture().get_image()
		var error := 0.0
		for y in size.y:
			for x in size.x:
				var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(size)
				var radial := 2.0 * uv - Vector2.ONE
				var end := uv - radial * radial.length_squared() * amount
				var green := sample(scene, uv.lerp(end, 1.0 / 3.0))
				var blue := sample(scene, uv.lerp(end, 2.0 / 3.0))
				var expected := (
					Color(scene.get_pixel(x, y).r, green.g, blue.b) + sample(bloom, uv) * 0.2
				)
				var pixel := actual.get_pixel(x, y)
				error = maxf(
					error,
					maxf(
						absf(pixel.r - expected.r),
						maxf(absf(pixel.g - expected.g), absf(pixel.b - expected.b))
					)
				)
		assert(error < 0.008, "RGB offset or bloom order differs from native formula")
		print("CHROMATIC_GPU amount=", amount, " max_error=", error)
	target.queue_free()


func check_stage_clock() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
	lab.stage.combat_clock.stop_frames(120, 0.02)
	lab.stage.chromatic.trigger(0, 1.0 / 60.0)
	assert(lab.stage.chromatic.intensity == 1.0)
	for frame in 45:
		await process_frame
	assert(lab.stage.combat_clock.scale_value == 0.0)
	assert(lab.stage.chromatic.intensity == 0.0 and lab.stage.chromatic.jobs.is_empty())
	var old_material: ShaderMaterial = lab.stage.chromatic.presentation
	assert(old_material.get_shader_parameter("chromatic_amount") == 0.0)
	lab.load_level(1)
	assert(lab.stage.chromatic.presentation != old_material)
	assert(lab.stage.chromatic.intensity == 0.0)
	lab.queue_free()
	await process_frame
