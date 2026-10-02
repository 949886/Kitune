extends SceneTree
const Stamp = preload("../Devices/ArrivalEffect/SpawnStamp.tscn")
const Rope = preload("../Devices/ArrivalEffect/SpawnRope.tscn")
const Batch = preload("../Devices/ArrivalEffect/ArrivalBatch.tscn")
const Workshop = preload("../Examples/SpawnWorkshop.tscn")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	create_timer(50, true, false, true).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var batch := Batch.instantiate()
	batch.position = Vector2(90, 20)
	batch.rotation = 0.3
	root.add_child(batch)
	var effects: Array[Node2D] = batch.spawn_wave([
		{"key": "stamp", "kind": "stamp", "position": Vector2(280, 446.4), "sort_y": 520},
		{"key": "rope", "kind": "rope", "position": Vector2(640, 561.6), "sort_y": 520, "gfx_scale_x": 1},
		{"key": "mirror", "kind": "rope", "position": Vector2(990, 541.6), "sort_y": 500, "gfx_scale_x": -1}])
	var stamp: Node2D
	var rope: Node2D
	var mirror: Node2D
	for effect: Node2D in effects:
		effect.set_process(false)
		match str(effect.get_meta("member_key")):
			"stamp": stamp = effect
			"rope": rope = effect
			"mirror": mirror = effect
	assert(mirror.z_index == 0 and mirror.scale.x == -1)
	assert(stamp.global_position.is_equal_approx(Vector2(280, 446.4)))
	assert(rope.scale.x == 1 and rope.masked.size() == 4)
	assert(stamp.visuals.size() == 12 and rope.visuals.size() == 7)
	assert(stamp.emitters.size() == 5 and rope.emitters.size() == 4)
	assert(not stamp.destroy_on_completion and rope.destroy_on_completion)
	assert(stamp.audio.get_child_count() == 1 and rope.audio.get_child_count() == 1)
	for effect in effects:
		for sample: Dictionary in effect.document.source_pose_samples:
			effect._sample(float(sample.time))
			for id: String in sample.transforms:
				var pose: Transform2D = effect.global_transform.affine_inverse() * effect.nodes[int(id)].global_transform
				var expected: Array = sample.transforms[id]
				assert(pose.x.distance_to(Vector2(expected[0], expected[1])) < 0.001)
				assert(pose.y.distance_to(Vector2(expected[2], expected[3])) < 0.001)
				assert(pose.origin.distance_to(Vector2(expected[4], expected[5])) < 0.002)
		effect._sample(0)
	# The Animator includes a non-rendering parent translation. Verify that the
	# entire stamp subtree moves, and tiled rods actually change their geometry.
	var start: Vector2 = stamp.visuals[1081].global_position
	var height: float = stamp.visuals[1119].destination.size.y
	for effect in effects: effect.advance_animation(0.8)
	assert(stamp.visuals[1081].global_position.distance_to(start) > 100)
	assert(not is_equal_approx(stamp.visuals[1119].destination.size.y, height))
	assert(rope.visuals[1082].texture != null)
	for light: Dictionary in stamp.light_states:
		assert(light.world_transform == stamp.nodes[int(light.go)].global_transform)
	await frames(3)
	# Check the actual shader output, holding particle positions fixed so the
	# only changed pixels come from the original rectangular SpriteMask.
	for effect in effects:
		for emitter: Node in effect.emitters: emitter.set_process(false)
	await RenderingServer.frame_post_draw
	var masked_pixels := root.get_texture().get_image().get_data()
	for binding: Dictionary in rope.masked:
		binding.material.set_shader_parameter("mask_enabled", false)
	await RenderingServer.frame_post_draw
	assert(masked_pixels != root.get_texture().get_image().get_data())
	rope._update_masks()
	for effect in effects:
		for emitter: Node in effect.emitters: emitter.set_process(emitter.animation_active)
	if not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	# Custom time scale affects Animator only. Already active particles keep
	# using scaled game delta, just like the source's non-ITimeObject particles.
	batch.custom_time_scale = 0
	for effect in effects: effect.advance_animation(4)
	assert(is_equal_approx(stamp.elapsed, 0.8) and is_equal_approx(rope.elapsed, 0.8))
	var particle_clock: float = rope.emitters[0].clock
	await frames(3)
	assert(rope.emitters[0].clock > particle_clock)
	batch.custom_time_scale = 1
	for effect in effects: effect.advance_animation(0.4)
	assert(rope.nodes[1082].visible)
	# The actual prop hides at 1.2166667, one frame after actor arrival.
	for effect in effects: effect.advance_animation(0.02)
	assert(not rope.nodes[1082].visible)
	var old_particles := []
	for emitter: Node in stamp.emitters:
		if emitter.particles.size() > 0:
			old_particles.append(weakref(emitter.particles[0].visual))
			emitter.set_animation_visibility(false)
			emitter.set_animation_visibility(true)
	await frames(2)
	for ref: WeakRef in old_particles: assert(ref.get_ref() == null)
	# Exactly one normalized cycle is not enough for the coroutine's > 1 test.
	rope.advance_animation(float(rope.document.clip.length) - rope.elapsed)
	assert(not rope.is_queued_for_deletion())
	rope.advance_animation(0.001)
	assert(rope.is_queued_for_deletion())
	stamp.advance_animation(10)
	assert(stamp.completed and not stamp.is_queued_for_deletion())
	var old: WeakRef = weakref(stamp)
	batch.queue_free()
	await frames(3)
	assert(old.get_ref() == null)
	# Real entry into the delayed-spawn workshop must create source effects,
	# and retry must release even the source stamp that never self-destructs.
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(4)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D; event.pressed = true; Input.parse_input_event(event)
	for frame in 180:
		await frames(1)
		if workshop.arrivals.batches_started > 0: break
	event = InputEventKey.new(); event.physical_keycode = KEY_D; event.pressed = false; Input.parse_input_event(event)
	assert(workshop.arrivals.batches_started == 1 and workshop.arrivals.get_child_count() == 4)
	old = weakref(workshop.arrivals)
	workshop.queue_free()
	await frames(3)
	assert(old.get_ref() == null)
	print("PORTABLE_ARRIVAL_EFFECT_PASS")
	quit(0)
