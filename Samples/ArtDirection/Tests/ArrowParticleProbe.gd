extends SceneTree
## Source arrow effect pixels, persistent distance emission, debris rotation and URP colors.

const Effect = preload("res://Samples/ArtDirection/Runtime/OriginalParticleEffect.gd")
const Values = preload("res://Samples/ArtDirection/Runtime/UnityParticleValues.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func make_effect(stage: Node, key: String, point: Vector2) -> Node2D:
	var result := Effect.new()
	stage.add_child(result)
	result.position = point
	result.configure(key, stage.sort_depth, null, 43891)
	result.set_process(false)
	for emitter: Node in result.emitters:
		emitter.set_process(false)
	return result


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	var impact := make_effect(lab.stage, "Eff_ArrowDestroy", lab.player.position + Vector2(50, -30))
	var flight := make_effect(lab.stage, "ArrowFlight", lab.player.position)
	assert(impact.emitters.size() == 5 and flight.emitters.size() == 2)
	for effect: Node in [impact, flight]:
		for emitter: Node in effect.emitters:
			var pixels: Image = emitter.texture.get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(pixels.get_data())
			assert(hash.finish().hex_encode() == emitter.data.texture.pixel_sha256)
			emitter.advance(0.01)
	assert(impact.emitters[0].emitted == 8)
	for index in range(1, 5):
		assert(impact.emitters[index].emitted == 1)
	for index in 3:
		var material: ShaderMaterial = impact.emitters[index].shared_material
		assert(material.shader.resource_path.ends_with("OriginalUnlitParticle.gdshader"))
		assert(material.get_shader_parameter("color_mode") == (1 if index == 0 else 2))
		assert(material.get_shader_parameter("color_operation") == Vector2(1, 0))
	for index in [3, 4]:
		var emitter: Node = impact.emitters[index]
		var particle: Dictionary = emitter.particles[0]
		var before := float(particle.rotation)
		emitter.advance(0.1)
		var angular_speed := Values.number(emitter.system.RotationModule.curve)
		assert(is_equal_approx(float(particle.rotation) - before, angular_speed * 0.1))
		assert(signf(angular_speed) == (-1.0 if index == 3 else 1.0))

	# A stationary arrow creates no flight particles. Loop duration is not a lifetime.
	for emitter: Node in flight.emitters:
		emitter.set_process(true)
		emitter.advance(1.2)
		assert(emitter.is_processing() and emitter.emitted == 0)
		emitter.set_process(false)
	var traveled_units := 0.0
	for frame in 90:
		flight.position.x += 8.0
		traveled_units += 0.5
		for emitter: Node in flight.emitters:
			emitter.advance(1.0 / 60.0)
	for emitter: Node in flight.emitters:
		var rate := Values.number(
			emitter.system.EmissionModule.rateOverDistance, 0, emitter.distance_factor
		)
		assert(emitter.emitted == floori(traveled_units * rate))
		assert(emitter.emitted > 0 and not emitter.particles.is_empty())
		assert(not emitter.particles[0].local)
		var particle: Dictionary = emitter.particles[0]
		var before: Vector2 = particle.visual.global_position
		flight.position.y += 100.0
		emitter._update(particle, 0.0)
		assert(particle.visual.global_position.is_equal_approx(before))
		flight.position.y -= 100.0
		var count := int(emitter.emitted)
		emitter.advance(0.25)
		assert(emitter.emitted == count, "Stationary emitter must not keep emitting by time")

	# Flight follows launch rotation; rifle muzzle effects keep their existing root-only behavior.
	var actor := Node2D.new()
	lab.stage.add_child(actor)
	actor.position = lab.player.position
	actor.rotation = -0.6
	flight.follow_actor = actor
	flight.follow_rotation = true
	flight.emitters[0].set_process(true)
	flight._process(0.0)
	flight.emitters[0].set_process(false)
	assert(is_equal_approx(flight.global_rotation, actor.global_rotation))
	var sources: Array = []
	for index in 3:
		sources.append(impact.emitters[index].data.material)
	flight.queue_free()
	if DisplayServer.get_name() != "headless":
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_arrow_impact.png")
	lab.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await verify_gpu(sources)
	print("ARROW_PARTICLE_PASS")
	quit()


func verify_gpu(sources: Array) -> void:
	# Compare all three authored materials against CPU color algebra, including alpha.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 32)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var texel := Color(0.31, 0.52, 0.71, 0.63)
	var vertex := Color(0.83, 0.24, 0.42, 0.72)
	var pixels := Image.create(1, 1, false, Image.FORMAT_RGBAF)
	pixels.fill(texel)
	var expected: Array[Color] = []
	for index in 3:
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(pixels)
		sprite.position = Vector2(index * 32 + 16, 16)
		sprite.scale = Vector2(32, 32)
		sprite.modulate = vertex
		var material := ShaderMaterial.new()
		material.shader = load("res://Samples/ArtDirection/Shaders/OriginalUnlitParticle.gdshader")
		material.set_shader_parameter("linear_framebuffer", true)
		material.set_shader_parameter("material_tint", Assets.color(sources[index].color))
		material.set_shader_parameter("color_mode", 1 if index == 0 else 2)
		material.set_shader_parameter("color_operation", Vector2(1, 0))
		sprite.material = material
		viewport.add_child(sprite)
		# Float textures are linear; vertex and source_color uniforms decode sRGB.
		var base := texel * Assets.color(sources[index].color).srgb_to_linear()
		var tint := vertex.srgb_to_linear()
		var color: Color
		if index == 0:
			color = Color.from_hsv(tint.h, tint.s, base.v)
		else:
			color = base + tint
		color *= base.a * tint.a
		expected.append(color)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var maximum_error := 0.0
	for index in 3:
		var actual := result.get_pixel(index * 32 + 16, 16)
		var reference := expected[index]
		maximum_error = maxf(
			maximum_error,
			maxf(
				absf(actual.r - reference.r),
				maxf(absf(actual.g - reference.g), absf(actual.b - reference.b))
			)
		)
	assert(maximum_error < 0.006, "URP particle color modes diverged: %f" % maximum_error)
	print("ARROW_PARTICLE_GPU_PASS error=", maximum_error)
	viewport.queue_free()
	await process_frame
