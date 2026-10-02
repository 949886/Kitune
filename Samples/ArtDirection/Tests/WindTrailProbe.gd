extends SceneTree
## Native ambient particles, birth-only buff colors, dust gates and water registration.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node = lab.player
	var control: Node = player.wind_trail
	control.advance()
	var trail: Node = control.trail
	var emitter: Node = trail.emitters[0]
	assert(trail.follow_actor == player.stamina_feedback.anchor)
	assert(emitter.system.looping and emitter.system.playOnAwake)
	assert(emitter.system.EmissionModule.rateOverTime.scalar == 0.0)
	assert(emitter.system.moveWithTransform == 1)
	assert(absf(emitter.pose.origin.y + 0.17) < 0.0001)
	verify_pixels(emitter)
	emitter.advance(0.1)
	assert(emitter.emitted == 0, "Standing still must not emit the distance trail")
	trail.position.x += 160.0
	emitter.advance(0.1)
	assert(emitter.emitted >= 5 and emitter.emitted <= 10)
	assert(player.wind_buff.level == 0, "Ambient trail exists without a wind buff")
	var first: Dictionary = emitter.particles[0]
	var white: Color = first.color
	assert(white == Color.WHITE)
	var old_position: Vector2 = first.visual.global_position
	player.wind_buff.level = 1
	player.wind_buff.ratio = 0.25
	control.advance()
	emitter._spawn()
	assert(emitter.particles[-1].color == Color(1.0, 0.25, 0.25))
	assert(first.color == white, "Changing startColor must not recolor existing particles")
	trail.position.x += 80.0
	emitter._update(first, 0.0)
	assert(first.visual.global_position.is_equal_approx(old_position))
	player.wind_buff.ratio = 0.75
	control.advance()
	emitter._spawn()
	assert(emitter.particles[-1].color == Color(1.0, 0.75, 0.75))
	player.wind_buff.ratio = 0.0
	control.advance()
	assert(emitter.start_color_override == Color(1.0, 0.75, 0.75))
	# Observe actual stage effect creation, excluding the independent ambient emitter.
	var dust: Array[Node] = []
	lab.stage.effect_started.connect(
		func(effect: Node):
			if effect.effect_key == control.settings.dust:
				dust.append(effect)
	)
	player.wind_buff.ratio = 0.5
	player.sprite.play("run", true)
	player.action_state = ""
	control.advance()
	assert(dust.is_empty(), "The native initial previous time suppresses frame-zero dust")
	player.facing = -1.0
	player.sprite.elapsed = 16.0 / 60.0
	control.advance()
	assert(dust.size() == 1 and dust[0].scale.x == -1.0)
	verify_pixels(dust[0].emitters[0])
	assert(dust[0].follow_actor == null)
	player.sprite.elapsed = 36.0 / 60.0
	control.advance()
	assert(dust.size() == 2)
	control.advance()
	assert(dust.size() == 2, "A stationary animation frame must not repeat its dust")
	player.sprite.elapsed = float(player.sprite.clips.run.length) + 0.001
	control.advance()
	assert(dust.size() == 2, "Preserve the source's wrap-around comparison")
	player.source_time_scale = 0.0
	var before: float = first.age
	emitter.advance(0.1)
	assert(first.age > before, "The ambient particle clock is independent of player hit-stop")
	lab.water_capture.particles.sync()
	for particle: Dictionary in emitter.particles:
		var copy: Sprite2D = lab.water_capture.particles.pairs[particle.visual.get_instance_id()]
		assert(copy.modulate == particle.visual.modulate)
		assert(copy.global_transform == particle.visual.global_transform)
		assert(copy.material != particle.visual.material)
	for effect: Node in dust:
		effect.emitters[0].advance(0.1)
	lab.water_capture._process(0.0)
	if DisplayServer.get_name() != "headless":
		for collection: Array in [
			lab.water_capture.stage_pairs,
			lab.water_capture.actor_pairs,
			lab.water_capture.line_pairs,
			lab.water_capture.marker_pairs
		]:
			for pair: Dictionary in collection:
				pair.copy.hide()
		lab.water_capture.camera.position = trail.global_position
		lab.water_capture.camera.force_update_scroll()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = lab.water_capture.viewport.get_texture().get_image()
		assert(image.get_used_rect().size.x > 5 and image.get_used_rect().size.y > 5)
		image.save_png("res://tmp/art-direction/inari_wind_trail_water.png")
		print("WIND_TRAIL_GPU water_bounds=", image.get_used_rect())
	var retired: WeakRef = weakref(trail)
	lab.load_level(0)
	await process_frame
	assert(retired.get_ref() == null)
	lab.queue_free()
	await process_frame
	print("WIND_TRAIL_PASS")
	quit()


func verify_pixels(emitter: Node) -> void:
	var pixels: Image = emitter.texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pixels.get_data())
	assert(hash.finish().hex_encode() == emitter.data.texture.pixel_sha256)
