extends SceneTree
## Source presets are exercised through actual overlaps, then the source camera
## renderer is driven by a walking/jumping host in a renamed, isolated project.
const Zone = preload("../Devices/CameraZone/CameraDistanceZone.tscn")
const Controller = preload("../Devices/CameraZone/CameraZoneController.tscn")
const Workshop = preload("../Examples/CameraZoneWorkshop.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var base: String = get_script().resource_path.get_base_dir() + "/.."


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


func actor() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(2, 2)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector2(-10000, -10000)
	return body


func source_presets() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/Assets/CameraZone/device.json"))
	assert(evidence.records.size() == 35 and evidence.scanned_headers.size() == 60)
	var disabled := 0
	for id: String in evidence.records:
		var fixture := Node2D.new()
		fixture.position = Vector2(123, -85)
		fixture.rotation = 0.3
		root.add_child(fixture)
		var player := actor()
		fixture.add_child(player)
		var controller := Controller.instantiate()
		fixture.add_child(controller)
		controller.bind_actor(player)
		controller.set_process(false)
		var zone := Zone.instantiate()
		zone.settings = load(base + "/Devices/CameraZone/Presets/" + id + ".tres")
		zone.transform = zone.settings.source_transform
		zone.position = Vector2.ZERO
		fixture.add_child(zone)
		zone.bind_controller(controller)
		var source: Dictionary = evidence.records[id].source
		var fields: Dictionary = source.fields
		var box: Dictionary = evidence.records[id].box
		assert(zone.settings.trigger_size.is_equal_approx(Vector2(box.m_Size.x, box.m_Size.y) * 16))
		assert(zone.settings.trigger_offset.is_equal_approx(Vector2(box.m_Offset.x, -box.m_Offset.y) * 16))
		player.global_position = zone.to_global(zone.settings.trigger_offset)
		await frames(4)
		if not zone.settings.initially_active:
			disabled += 1
			assert(not zone.inside and zone.entries == 0)
			zone.set_active(true)
			await frames(4)
		assert(zone.inside and zone.entries == 1)
		var state: Dictionary = controller.target_state()
		if source.type == "CameraDistanceTrigger":
			assert(not state.fixed and state.depth == fields.offset.z and state.z_damping == fields.damping)
			assert(state.position.distance_to(player.global_position + Vector2(fields.offset.x, -fields.offset.y) * 16) < 0.01)
		else:
			assert(state.fixed and state.depth == fields.distance)
			var expected := Vector2(lerpf(zone.global_position.x, player.global_position.x, fields.xDamp), lerpf(zone.global_position.y, player.global_position.y, fields.yDamp))
			assert(state.position.distance_to(expected) < 0.01)
			assert(state.unlimited_soft_zone)
			controller.advance_realtime(0.19)
			assert(controller.unlimited_soft_zone)
			controller.advance_realtime(0.02)
			assert(not controller.unlimited_soft_zone)
		player.global_position = Vector2(-10000, -10000)
		await frames(4)
		assert(not zone.inside and zone.exits == 1 and zone.consumed == bool(fields.isOnce))
		assert(not controller.target_state().fixed)
		if source.type == "CameraDistanceTrigger":
			assert(controller.tracked_offset == Vector3.ZERO and controller.z_damping == 1)
		player.global_position = zone.to_global(zone.settings.trigger_offset)
		await frames(4)
		assert(zone.entries == (1 if fields.isOnce else 2))
		if fields.isOnce:
			zone.set_active(true)
			await frames(4)
			assert(zone.entries == 2 and not zone.source.fields.isOnce)
		var old: WeakRef = weakref(zone)
		fixture.queue_free()
		await frames(2)
		assert(old.get_ref() == null)
	assert(disabled == 2)
	print("CAMERA_35_PRESETS_PASS")


func lifecycle() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var player := actor()
	fixture.add_child(player)
	var controller := Controller.instantiate()
	fixture.add_child(controller)
	var busy := {"loading": true, "frozen": false}
	controller.bind_actor(player, Callable(), func(): return busy.loading, func(): return busy.frozen)
	controller.set_process(false)
	var zone := Zone.instantiate()
	zone.settings = load(base + "/Devices/CameraZone/Presets/level5_11933.tres")
	zone.scale = Vector2(70, 40)
	fixture.add_child(zone)
	zone.bind_controller(controller)
	player.position = zone.to_global(zone.settings.trigger_offset)
	await frames(4)
	assert(zone.inside and controller.pending_entries.size() == 1 and controller.fixed_zone == null)
	# An exit does not cancel WaitForSceneLoadComplete, including once-only exit.
	player.position = Vector2(10000, 0)
	await frames(4)
	assert(zone.consumed and controller.pending_entries.size() == 1)
	busy.loading = false
	await frames(2)
	assert(controller.fixed_zone == zone and controller.target_state().position == player.position)
	# Freeze prevents only creation of the soft-zone timer, not camera following.
	controller.advance_realtime(1)
	busy.frozen = true
	zone.set_active(true)
	player.position = zone.to_global(zone.settings.trigger_offset)
	await frames(4)
	assert(controller.fixed_zone == zone and not controller.unlimited_soft_zone)
	busy.frozen = false
	player.position = Vector2(10000, 0)
	await frames(4)
	assert(controller.unlimited_soft_zone)
	Engine.time_scale = 0.1
	controller.advance_realtime(0.21)
	assert(not controller.unlimited_soft_zone)
	Engine.time_scale = 1
	# Wrong body/layer never enters. Rebinding to a released actor is harmless.
	var other := actor()
	fixture.add_child(other)
	other.position = zone.to_global(zone.settings.trigger_offset)
	await frames(4)
	assert(not zone.inside)
	player.collision_layer = 8
	player.position = other.position
	await frames(4)
	assert(not zone.inside)
	player.queue_free()
	await frames(2)
	assert(not controller.accept_actor(other))
	fixture.queue_free()
	await frames(2)


func playable() -> void:
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(5)
	key(KEY_D, true)
	for frame in 170:
		await frames(1)
		if workshop.player.position.x > 620: break
	key(KEY_D, false)
	await frames(5)
	assert(workshop.distance_zone.inside and workshop.rig.renderer.camera_distance > 21.5)
	# Independent Cinemachine damper oracle: five seconds leaves 1% error.
	var rig: Node = workshop.rig.renderer
	rig.set_process(false)
	rig._set_camera_distance(21.5)
	for step in 60: rig.advance(5.0 / 60)
	assert(absf(rig.camera_distance - (25 - 3.5 * 0.01)) < 0.0001)
	rig.set_process(true)
	key(KEY_D, true)
	for frame in 650:
		await frames(1)
		if workshop.player.position.x > 2420: break
	key(KEY_D, false)
	await frames(4)
	assert(workshop.fixed_zone.inside and workshop.controller.fixed_zone == workshop.fixed_zone)
	var target_before: Vector2 = workshop.controller.target_state().position
	var player_before: Vector2 = workshop.player.position
	key(KEY_SPACE, true)
	await frames(10)
	key(KEY_SPACE, false)
	var target_after: Vector2 = workshop.controller.target_state().position
	assert(absf((target_after.y - target_before.y) - (workshop.player.position.y - player_before.y) * 0.2) < 2)
	if not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	key(KEY_D, true)
	await frames(160)
	key(KEY_D, false)
	await frames(3)
	assert(workshop.fixed_zone.consumed and workshop.controller.fixed_zone == null)
	key(KEY_A, true)
	await frames(160)
	key(KEY_A, false)
	assert(workshop.fixed_zone.entries == 1)
	var old: WeakRef = weakref(workshop.controller)
	workshop.queue_free()
	await frames(3)
	assert(old.get_ref() == null)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(16)
	await frames(4)
	old = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(old.get_ref() == null and not gallery.exhibit.fixed_zone.consumed)
	old = weakref(gallery.exhibit)
	gallery.select_exhibit(0)
	await frames(3)
	assert(old.get_ref() == null)
	gallery.queue_free()
	await frames(3)


func overlap_contract() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var player := actor()
	fixture.add_child(player)
	var controller := Controller.instantiate()
	fixture.add_child(controller)
	controller.bind_actor(player)
	var first := Zone.instantiate()
	var second := Zone.instantiate()
	second.settings = load(base + "/Devices/CameraZone/Presets/level12_9123.tres")
	fixture.add_child(first)
	fixture.add_child(second)
	first.bind_controller(controller)
	second.bind_controller(controller)
	player.position = Vector2.ZERO
	await frames(4)
	assert(first.inside and second.inside)
	assert(controller.tracked_offset.z == 2)
	# A source exit resets shared state even when another volume still overlaps.
	# It is the next Stay that reapplies the remaining volume, not a restore stack.
	first._exit(player)
	assert(controller.tracked_offset == Vector3.ZERO and controller.z_damping == 1)
	controller.refresh_overlaps()
	assert(controller.tracked_offset.z == 2 and controller.z_damping == 5)
	# Unloading a waiting region removes its pending callbacks and timer owners.
	var fixed := Zone.instantiate()
	fixed.settings = load(base + "/Devices/CameraZone/Presets/level5_11933.tres")
	fixture.add_child(fixed)
	fixed.bind_controller(controller)
	controller.loading = func(): return true
	await frames(4)
	assert(controller.pending_entries.size() == 1)
	# Multiple entries while loading start independent source waits. Unloading
	# must discard every callback owned by that region, not only the first.
	controller.enter(fixed)
	assert(controller.pending_entries.size() == 2)
	fixed.queue_free()
	await frames(2)
	assert(controller.pending_entries.is_empty() and controller.zones.size() == 2)
	fixture.queue_free()
	await frames(2)


func run() -> void:
	create_timer(55, true, false, true).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	await source_presets()
	await lifecycle()
	await overlap_contract()
	await playable()
	print("PORTABLE_CAMERA_ZONE_PASS")
	quit()
