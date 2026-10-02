extends SceneTree
const Platform = preload("../Devices/DisappearingPlatform/DisappearingPlatform.tscn")
const Workshop = preload("../Examples/DisappearingPlatformWorkshop.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var activations := 0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	var platform := Platform.instantiate()
	root.add_child(platform)
	platform.set_physics_process(false)
	assert(is_equal_approx(platform.disappear_after, 109.0 / 60.0))
	assert(is_equal_approx(platform.recover_after, 1.25))
	assert(platform.visuals.size() == 4)
	platform.activated.connect(func(): activations += 1)
	assert(platform.activate())
	assert(not platform.activate() and activations == 1)
	platform.advance(108.0 / 60.0)
	await frames(1)
	assert(platform.state == platform.State.COUNTDOWN and not platform.shape.disabled)
	platform.advance(1.0 / 60.0)
	await frames(1)
	assert(platform.state == platform.State.HIDDEN and platform.shape.disabled)
	platform.advance(1.24)
	assert(platform.state == platform.State.HIDDEN)
	platform.advance(0.01)
	await frames(1)
	assert(platform.state == platform.State.READY and not platform.shape.disabled)
	assert(platform._animation_index == 3)
	# Restoration is BEFORE the opening animation finishes; repeat contact queues
	# Active through Recover rather than cancelling the opening animation.
	assert(platform.activate() and platform._pending_active)
	platform.advance(0.3)
	assert(platform._animation_index == 1 and not platform._pending_active)
	platform.reset()
	assert(platform.state == platform.State.READY and platform._animation_index == 0)
	var original_settings: Resource = platform.settings
	platform.settings = platform.settings.duplicate()
	platform.settings.time_scale = 0
	platform.activate()
	platform.advance(10)
	assert(platform.elapsed == 0 and original_settings.time_scale == 1)
	platform.queue_free()
	await frames(2)
	# Every shipped preset must instantiate its own collision group and artwork.
	var folder: String = Platform.resource_path.get_base_dir()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/device.json"))
	assert(data.records.size() == 14)
	for key: String in data.records:
		var device := Platform.instantiate()
		device.settings = device.settings.duplicate()
		device.settings.source_key = key
		root.add_child(device)
		assert(device.shape.polygon.size() >= 4)
		device.queue_free()
	await frames(2)
	await physical_contacts()
	await keyboard_route()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(19)
	await frames(3)
	var previous: Node = gallery.exhibit
	gallery.select_exhibit(1)
	await frames(3)
	assert(not is_instance_valid(previous))
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_DISAPPEARING_PLATFORM_PASS")
	quit()


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func keyboard_route() -> void:
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(3)
	var actor: CharacterBody2D = workshop.player
	var destinations := [280.0, 510.0, 740.0, 930.0]
	for index in destinations.size():
		var launch_x: float = 120.0 if index == 0 else destinations[index - 1] + 25.0
		key(KEY_D, true)
		for frame in 60:
			if actor.position.x >= launch_x:
				break
			await frames(1)
		assert(actor.is_on_floor())
		key(KEY_SPACE, true)
		await frames(1)
		key(KEY_SPACE, false)
		var landed := false
		for frame in 70:
			await frames(1)
			if actor.position.x >= destinations[index]:
				key(KEY_D, false)
			if actor.is_on_floor():
				landed = true
				break
		key(KEY_D, false)
		assert(landed and absf(actor.position.y - [440, 370, 300, 230][index]) < 1)
	assert(actor.position.x >= 861)
	key(KEY_R, true)
	await frames(1)
	key(KEY_R, false)
	assert(actor.position.x == 120 and workshop.platforms.all(func(p): return p.state == 0))
	workshop.queue_free()
	await frames(2)


func physical_contacts() -> void:
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(2)
	var actor: CharacterBody2D = workshop.player
	var a: Node = workshop.platforms[0]
	var b: Node = workshop.platforms[1]
	# Standing on the floor and jumping at the underside cannot activate a group.
	await frames(3)
	assert(a.state == 0)
	actor.position = a.position + Vector2(0, 70)
	actor.velocity = Vector2(0, -440)
	await frames(10)
	assert(a.state == 0)
	actor.position = a.position + Vector2(60, 12)
	actor.velocity = Vector2.ZERO
	actor.left = true
	await frames(3)
	actor.left = false
	assert(a.state == 0)
	# Top landing uses real CharacterBody2D slide contacts, then solidity disappears
	# so the actor actually falls. A different instance remains ready throughout.
	actor.position = a.position + Vector2(0, -45)
	actor.velocity = Vector2.ZERO
	await frames(22)
	assert(actor.is_on_floor() and a.state == 1 and b.state == 0)
	var contact_count := 0
	for i in 110:
		await frames(1)
		if a.state == 2:
			contact_count += 1
			break
	assert(contact_count == 1)
	await frames(12)
	assert(actor.position.y > a.position.y + 8 and not actor.is_on_floor())
	if DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	await frames(70)
	assert(a.state == 0 and not a.shape.disabled)
	# A host-supplied dead predicate suppresses contact without a project singleton.
	a.bind_actor(actor, func(): return false)
	actor.position = a.position + Vector2(0, -45)
	actor.velocity = Vector2.ZERO
	await frames(25)
	assert(actor.is_on_floor() and a.state == 0)
	a.bind_actor(actor)
	await frames(2)
	assert(a.state == 1)
	# Leaving a platform does not cancel its countdown.
	actor.position = Vector2(120, 490)
	actor.velocity = Vector2.ZERO
	await frames(112)
	assert(a.state == 2 and b.state == 0)
	workshop.queue_free()
	await frames(2)
