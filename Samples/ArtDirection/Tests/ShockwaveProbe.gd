extends SceneTree
## Native layer boundary, particle age, selective pause and scene-color GPU sampling.

const ShaderSource = preload("res://Samples/ArtDirection/Shaders/OriginalShockwave.gdshader")


func _initialize() -> void:
	call_deferred("run")


func frames(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
	var capture: BackBufferCopy = lab.stage.sorting_capture
	assert(
		capture.settings.capture_layer == "Ground2" and capture.settings.capture_layer_value == 2
	)
	assert(capture.z_index > lab.stage.sort_depth([2, 30000]))
	assert(capture.z_index < lab.stage.sort_depth([3, -30000]))
	assert(capture.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT)
	var effect: Node = lab.stage.spawn_effect("Eff_PlayerThirdStack", lab.player.position, 0.0)
	var emitter: Node = effect.emitters[0]
	await frames(4)
	assert(emitter.is_shockwave and emitter.particles.size() == 1)
	var particle: Dictionary = emitter.particles[0]
	assert(particle.visual.visible)
	assert(particle.visual.material.shader == ShaderSource)
	assert(particle.visual.material != emitter.shared_material)
	assert(
		is_equal_approx(
			particle.visual.material.get_shader_parameter("age_percent"),
			particle.age / particle.life
		)
	)
	assert(is_equal_approx(particle.life, 0.6))
	var before: float = particle.age
	lab.stage.combat_clock.stop_frames(10, lab.player.tuning.fixed_timestep)
	await frames(3)
	assert(particle.age == before)
	await frames(55)
	assert(emitter.particles.is_empty())
	lab.queue_free()
	await frames()
	if DisplayServer.get_name() != "headless":
		await compare_gpu()
	print("SHOCKWAVE_PASS")
	quit()


func compare_gpu() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(128, 96)
	target.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var background := ColorRect.new()
	background.size = Vector2(target.size)
	var gradient := Shader.new()
	gradient.code = """
		shader_type canvas_item;
		render_mode unshaded;
		uniform float phase = 0.0;
		void fragment() {
			COLOR = vec4(UV.x * 0.5 + phase, UV.y * 0.5, 0.25, 1.0);
		}
	"""
	var background_material := ShaderMaterial.new()
	background_material.shader = gradient
	background.material = background_material
	target.add_child(background)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.z_index = 1
	target.add_child(copy)
	var intervening := ColorRect.new()
	intervening.size = Vector2(target.size)
	intervening.color = Color.YELLOW
	intervening.z_index = 2
	target.add_child(intervening)
	var shockwave := ColorRect.new()
	shockwave.size = Vector2(target.size)
	shockwave.z_index = 3
	var material := ShaderMaterial.new()
	material.shader = ShaderSource
	material.set_shader_parameter("distortion_strength", 0.4)
	material.set_shader_parameter("ring_size", 0.2)
	shockwave.material = material
	target.add_child(shockwave)
	var foreground := ColorRect.new()
	foreground.size = Vector2(4, target.size.y)
	foreground.color = Color.BLUE
	foreground.z_index = 4
	target.add_child(foreground)
	for age: float in [0.0, 0.25, 0.5, 0.9]:
		material.set_shader_parameter("age_percent", age)
		background_material.set_shader_parameter("phase", age * 0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		var actual := target.get_texture().get_image()
		var error := 0.0
		var displaced := 0
		for y in range(1, target.size.y, 3):
			for x in range(5, target.size.x, 3):
				var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(target.size)
				var radial := Vector2(uv.x, 1.0 - uv.y) * 2.0 - Vector2.ONE
				var radius := radial.length()
				var t := clampf((radius - age + 0.2) / 0.4, 0.0, 1.0)
				var eased := t * t * (3.0 - 2.0 * t)
				var amount := clampf((1.0 - radius) * eased * (1.0 - eased) * 0.4, 0.0, 1.0)
				var offset := radial.normalized() * amount * (1.0 - age)
				var sample_uv := uv + Vector2(offset.x, -offset.y)
				var edge := Vector2(0.5, 0.5) / Vector2(target.size)
				sample_uv = sample_uv.clamp(edge, Vector2.ONE - edge)
				var expected := Vector3(sample_uv.x * 0.5 + age * 0.1, sample_uv.y * 0.5, 0.25)
				var pixel := actual.get_pixel(x, y)
				var difference := (Vector3(pixel.r, pixel.g, pixel.b) - expected).abs()
				error = maxf(error, maxf(difference.x, maxf(difference.y, difference.z)))
				if offset.length() > 0.0001:
					displaced += 1
		assert(actual.get_pixel(1, 1).b > 0.99, "Foreground must remain above the shockwave")
		assert(displaced > 0)
		print("SHOCKWAVE_GPU age=", age, " max_error=", error, " displaced=", displaced)
		assert(
			error < 0.007, "Scene snapshot boundary, current-frame copy or radial formula differs"
		)
	target.queue_free()
	await process_frame
