extends SceneTree
const Zone = preload("../Devices/ShurikenDistance/ShurikenDistanceZone.tscn")
const RangeState = preload("../Devices/ShurikenDistance/ShurikenRange.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var base: String = get_script().resource_path.get_base_dir() + "/.."
var loading := false


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


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
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/Assets/ShurikenDistance/device.json"))
	assert(evidence.records.size() == 2 and evidence.scanned_headers.size() == 60)
	for id: String in evidence.records:
		var source: Dictionary = evidence.records[id]
		assert(source.audit.roundtrip_equal)
		var fixture := Node2D.new()
		fixture.position = Vector2(123, 65)
		fixture.rotation = 0.3
		fixture.scale = Vector2(1.4, 0.9)
		root.add_child(fixture)
		var player := actor()
		fixture.add_child(player)
		var state := RangeState.instantiate()
		fixture.add_child(state)
		var zone := Zone.instantiate()
		zone.settings = load(base + "/Devices/ShurikenDistance/Presets/" + id + ".tres")
		assert(zone.settings.additive_distance == float(source.fields.additiveDistance))
		assert(zone.settings.trigger_size.is_equal_approx(Vector2(source.box.m_Size.x, source.box.m_Size.y) * evidence.baseline.pixels_per_unit))
		zone.transform = zone.settings.source_transform
		zone.position = Vector2.ZERO
		zone.bind_actor(player, func(): return loading)
		zone.bind_range(state)
		fixture.add_child(zone)
		player.global_position = zone.to_global(zone.settings.trigger_offset)
		await frames(4)
		assert(zone.calls > 0 and state.additive_distance == zone.settings.additive_distance)
		var bonus: float = state.capture_bonus()
		var captured: float = state.limit_for(bonus)
		assert(captured == (evidence.baseline.base_distance + source.fields.additiveDistance) * evidence.baseline.pixels_per_unit)
		var calls: int = zone.calls
		await frames(4)
		assert(zone.calls == calls)
		loading = true
		player.position = Vector2(-10000, -10000)
		await frames(4)
		assert(state.additive_distance == 0 and state.current_limit() < captured)
		player.global_position = zone.to_global(zone.settings.trigger_offset)
		await frames(4)
		assert(state.additive_distance == zone.settings.additive_distance)
		assert(not state.exceeds_limit(Vector2(captured, 0), Vector2.ZERO, captured))
		assert(state.exceeds_limit(Vector2(captured + 0.01, 0), Vector2.ZERO, captured))
		state.settings = state.settings.duplicate(true)
		state.settings.base_distance += 3.0
		assert(state.limit_for(bonus) == captured + 3.0 * state.settings.pixels_per_unit)
		loading = false
		fixture.queue_free()
		await frames(2)


func overlaps_and_filtering() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var player := actor()
	fixture.add_child(player)
	var stranger := actor()
	fixture.add_child(stranger)
	var state := RangeState.instantiate()
	fixture.add_child(state)
	var zones := []
	for x in [0, 80]:
		var zone := Zone.instantiate()
		zone.settings = zone.settings.duplicate(true)
		zone.settings.trigger_size = Vector2(120, 120)
		zone.settings.trigger_offset = Vector2.ZERO
		zone.settings.additive_distance += x # Distinct values expose overwrite order.
		zone.position.x = x
		zone.bind_actor(player)
		zone.bind_range(state)
		fixture.add_child(zone)
		zones.append(zone)
	stranger.position = Vector2.ZERO
	await frames(4)
	assert(state.additive_distance == 0)
	player.collision_layer = 8
	player.position = Vector2(-40, 0)
	await frames(4)
	assert(state.additive_distance == 0)
	player.collision_layer = 4
	await frames(4)
	assert(state.additive_distance == zones[0].settings.additive_distance)
	player.position.x = 40
	await frames(4)
	assert(state.additive_distance == zones[1].settings.additive_distance)
	player.position.x = 90
	await frames(4)
	assert(state.additive_distance == 0, "Exiting one zone resets even inside another")
	zones[1].interactive_shuriken()
	assert(state.additive_distance == zones[1].settings.additive_distance)
	fixture.queue_free()
	await frames(2)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func run() -> void:
	root.size = Vector2i(1280, 720)
	await source_presets()
	await overlaps_and_filtering()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(18)
	await frames(5)
	var room: Node = gallery.exhibit
	key(KEY_F, true)
	key(KEY_F, false)
	await frames(40)
	assert(room.expired == 1 and room.hits == 0)
	key(KEY_D, true)
	await frames(35)
	key(KEY_D, false)
	assert(room.player.range_state.additive_distance > 0)
	key(KEY_F, true)
	key(KEY_F, false)
	await frames(2)
	var captured: float = room.projectile.captured_limit
	key(KEY_A, true)
	await frames(35)
	key(KEY_A, false)
	await frames(5)
	assert(room.hits == 1 and room.player.range_state.additive_distance == 0)
	assert(room.projectile.captured_limit == captured and room.projectile.stuck)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shuriken-distance-workshop.png")
	var old: WeakRef = weakref(room)
	key(KEY_R, true)
	key(KEY_R, false)
	await frames(4)
	assert(old.get_ref() == null and gallery.exhibit.hits == 0)
	old = weakref(gallery.exhibit.player.range_state)
	gallery.select_exhibit(0)
	await frames(3)
	assert(old.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_SHURIKEN_DISTANCE_PASS")
	quit()
