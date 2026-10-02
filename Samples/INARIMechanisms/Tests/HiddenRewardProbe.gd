extends SceneTree
const Workshop = preload("../Examples/RewardWorkshop.tscn")
const Reward = preload("../Devices/HiddenReward/HiddenReward.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func started_count(reward: Node) -> int:
	var count := 0
	for charge: Node in reward.mechanism.charges.values():
		if charge.started:
			count += 1
	return count


func run() -> void:
	create_timer(50).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	var first: Node = workshop.rewards[0]
	var second: Node = workshop.rewards[1]
	var actor: Node = workshop.player
	var events: Array = []
	first.audio.event_played.connect(func(event): events.append(event))
	await frames(8)
	assert(first.visual_instances.size() == 9 and first.document.sprite_info.size() == 32)
	assert(first.ambient_emitters.size() == 8 and first.fragment_emitters.size() == 7)
	var distortion: Node
	for visual: Node in first.visual_instances:
		if visual.data.has("square_distortion"):
			distortion = visual
	assert(distortion != null)
	assert(distortion.mesh.surface_get_array_len(0) == 12)
	assert(distortion.mesh.surface_get_array_index_len(0) == 30)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var snapshot := root.get_texture().get_image()
		var sample: Vector2 = second.get_global_transform_with_canvas() * Vector2(50, 0)
		var color := snapshot.get_pixelv(Vector2i(sample))
		assert(
			color.r < 0.7 and color.g < 0.7,
			"Refraction must not draw the source circle as opaque white"
		)
	for emitter: Node in first.ambient_emitters:
		assert(not emitter.animation_active and emitter.emitted == 0)
	assert(not first.is_collected() and actor.buff.level == 0 and actor.is_on_floor())
	key(KEY_D, true)
	for frame in 120:
		await frames(1)
		if first.is_collected():
			break
	key(KEY_D, false)
	assert(workshop.reward_count == 1 and workshop.refreshes == 0 and actor.buff.level == 0)
	assert(started_count(first) == 6, "Part_7 component is disabled until the last authored key")
	await frames(10)
	assert(started_count(first) == 6)
	assert(distortion.material.get_shader_parameter("distortion_strength") < 0.3)
	assert(not distortion.scale.is_equal_approx(distortion.base_scale))
	var emitter: Node = first.fragment_emitters[0]
	assert(emitter.animation_active and emitter.frame_transform.is_valid())
	first.motion_time_scale = 0
	await frames(3)
	var charge: Node = first.mechanism.charges.values()[1]
	var position: Vector2 = charge.visual.global_position
	var progress: float = charge.progress
	await frames(15)
	assert(charge.progress == progress and charge.visual.global_position == position)
	first.motion_time_scale = 1
	if not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	await frames(300)
	assert(first.received_fragment_count() == 7 and workshop.money == 7)
	assert(events.count("reward_soul") == 7 and events.count("reward_prism_get") == 7)
	assert(first.completion_sent)
	assert(not distortion.visible)
	for source_light: Dictionary in first.mechanism.lights.values():
		assert(not source_light.enabled and is_zero_approx(source_light.energy))
	# A captured fragment's source GameObject remains enabled: its particle
	# children must continue without moving back to the reward's original point.
	for trail: Node in first.fragment_emitters:
		assert(trail.animation_active and trail.emitted > 0)
	key(KEY_D, true)
	for frame in 220:
		await frames(1)
		if actor.buff.level > 0:
			break
	key(KEY_D, false)
	await frames(65)
	assert(actor.buff.level == 1 and actor.buff.ratio > 0.1)
	key(KEY_D, true)
	for frame in 150:
		await frames(1)
		if second.is_collected():
			break
	key(KEY_D, false)
	assert(workshop.reward_count == 2 and workshop.refreshes == 1)
	assert(actor.buff.level == 1 and actor.buff.ratio < 0.05)
	await frames(300)
	assert(second.received_fragment_count() == 7 and workshop.money == 14)
	var old: WeakRef = weakref(first)
	var old_trail: WeakRef = weakref(emitter)
	key(KEY_R, true)
	key(KEY_R, false)
	await frames(6)
	assert(old.get_ref() == null and old_trail.get_ref() == null)
	assert(workshop.reward_count == 2 and workshop.money == 14 and workshop.refreshes == 1)
	for restored: Node in workshop.rewards:
		assert(restored.is_collected() and restored.mechanism.charges.is_empty())
		for visual: Node in restored.visual_instances:
			assert(not visual.visible)
		for particle: Node in restored.ambient_emitters:
			assert(not particle.animation_active and particle.emitted == 0)
	workshop.queue_free()
	await frames(3)
	await isolated_fixture()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(9)
	await frames(3)
	var device: WeakRef = weakref(gallery.exhibit.rewards[0])
	gallery.select_exhibit(0)
	await frames(3)
	assert(device.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_HIDDEN_REWARD_PASS")
	quit()


func isolated_fixture() -> void:
	var actor := CharacterBody2D.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(16, 28)
	shape.shape = box
	actor.add_child(shape)
	root.add_child(actor)
	var reward := Reward.instantiate()
	reward.position = Vector2(3000, 3000)
	reward.rotation = PI / 2
	reward.scale = Vector2.ONE * 1.5
	reward.actor_layers = 32
	reward.settings = reward.settings.duplicate(true)
	reward.settings.currency_per_fragment = 3
	root.add_child(reward)
	actor.position = reward.position
	await frames(4)
	assert(not reward.is_collected())
	var allowed := {"value": false}
	reward.bind_actor(actor, shape, func(): return allowed.value)
	await reenter(actor, reward)
	assert(not reward.is_collected())
	allowed.value = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	await reenter(actor, reward)
	assert(not reward.is_collected())
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 4
	await reenter(actor, reward)
	assert(not reward.is_collected())
	actor.collision_layer = 32
	var currency: Array = []
	reward.currency_requested.connect(func(_actor, amount): currency.append(amount))
	await frames(4)
	assert(reward.is_collected())
	await frames(300)
	assert(reward.received_fragment_count() == 7 and currency.size() == 7)
	for amount in currency:
		assert(amount == 3)
	var source: Dictionary = reward.document.record.trigger
	var size: Vector2 = reward.mechanism.get_child(0).shape.size
	assert(size == Vector2(source.size[0], source.size[1]))
	for trail: Node in reward.fragment_emitters:
		var frame: Transform3D = trail._world_pose()
		assert(frame.origin.distance_to(Vector3(3000 / 16.0, -3000 / 16.0, 0)) > 0.01)
	actor.queue_free()
	await frames(4)
	for trail: Node in reward.fragment_emitters:
		assert(not trail.animation_active)
	assert(currency.size() == 7)
	reward.queue_free()
	await frames(3)
	# Destruction during homing cannot redirect fragments to a new actor or
	# call currency callbacks after the original recipient has disappeared.
	actor = CharacterBody2D.new()
	actor.collision_layer = 4
	shape = CollisionShape2D.new()
	shape.shape = box
	actor.add_child(shape)
	actor.position = Vector2(5000, 5000)
	root.add_child(actor)
	reward = Reward.instantiate()
	reward.position = actor.position
	reward.bind_actor(actor, shape)
	root.add_child(reward)
	await frames(3)
	assert(reward.is_collected())
	actor.queue_free()
	await frames(100)
	assert(reward.received_fragment_count() == 0 and reward.completion_sent)
	for fragment: Node in reward.mechanism.charges.values():
		assert(fragment.finished and not fragment.received)
	reward.queue_free()
	await frames(3)


func reenter(actor: Node2D, reward: Node2D) -> void:
	actor.position = reward.position + Vector2(1000, 1000)
	await frames(3)
	actor.position = reward.position
	await frames(3)
