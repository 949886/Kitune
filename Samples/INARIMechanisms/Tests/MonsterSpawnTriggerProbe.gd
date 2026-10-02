extends SceneTree
const Trigger = preload("../Devices/MonsterSpawnTrigger/MonsterSpawnTrigger.tscn")
const Workshop = preload("../Examples/SpawnWorkshop.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var fixture: Node2D
var actor: CharacterBody2D
var entered_count := 0
var spawned_count := 0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func center(trigger: Node2D) -> Vector2:
	return trigger.to_global(trigger.settings.trigger_transform * trigger.settings.trigger_offset)


func make_fixture(preset := "level6_11494", restored := false) -> Node2D:
	var node := Trigger.instantiate()
	var base := (Trigger as PackedScene).resource_path.get_base_dir()
	node.settings = load(base + "/Presets/" + preset + ".tres").duplicate(true)
	node.position = Vector2(3000, 3000)
	node.rotation = PI / 2
	node.scale = Vector2(0.7, 1.2)
	node.actor_layers = 32
	node.restored_activated = restored
	node.bind_actor(actor)
	node.entered.connect(func(_body): entered_count += 1)
	node.spawn_requested.connect(func(): spawned_count += 1)
	return node


func enter(trigger: Node2D) -> void:
	actor.position = Vector2(-3000, -3000)
	await frames(3)
	actor.position = center(trigger)
	await frames(3)


func fixture_checks() -> void:
	actor = CharacterBody2D.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(12, 20)
	shape.shape = box
	actor.add_child(shape)
	root.add_child(actor)
	var base := (Trigger as PackedScene).resource_path.get_base_dir()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/../../Assets/MonsterSpawnTrigger/device.json"))
	assert(document.records.size() == 5)
	for preset: String in document.records:
		var setting: Resource = load(base + "/Presets/" + preset + ".tres")
		var source: Dictionary = document.records[preset]
		assert(setting.collider_enabled == bool(source.record.trigger.enabled))
		assert(setting.delay_seconds == source.record.fields.spawnTerm)
		assert(setting.on_field == source.target.on_field)
		assert(setting.trigger_size == Vector2(source.record.trigger.size[0], source.record.trigger.size[1]))
		assert(setting.trigger_offset == Vector2(source.record.trigger.offset[0], source.record.trigger.offset[1]))
	fixture = make_fixture()
	var host := {"loading": true, "eligible": true}
	fixture.bind_actor(actor, func(): return host.eligible, func(): return host.loading)
	actor.position = center(fixture)
	root.add_child(fixture)
	fixture.mechanism.set_process(false)
	await frames(4)
	assert(entered_count == 0 and fixture.mechanism.waits.is_empty())
	host.loading = false
	await frames(3)
	assert(entered_count == 0, "Ignored Enter is not retried on Stay")
	host.eligible = false
	await enter(fixture)
	assert(entered_count == 0)
	host.eligible = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	await enter(fixture)
	assert(entered_count == 0)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 4
	await enter(fixture)
	assert(entered_count == 0)
	actor.position = Vector2(-3000, -3000)
	await frames(3)
	actor.collision_layer = 32
	await enter(fixture)
	assert(entered_count == 1 and fixture.mechanism.waits.size() == 1)
	assert(fixture.snapshot() == {"isActivated": false})
	fixture.mechanism.advance_realtime(0.1) # First keepWaiting poll arms the deadline.
	fixture.mechanism.advance_realtime(0.4)
	assert(spawned_count == 0)
	fixture.mechanism.spawn_term = 0.1
	await enter(fixture)
	assert(entered_count == 2 and fixture.mechanism.waits.size() == 2)
	var at_request: Array = []
	var saved: Array = []
	fixture.save_requested.connect(func(record): saved.append(record))
	fixture.spawn_requested.connect(func(): at_request.append(fixture.snapshot()))
	fixture.mechanism.advance_realtime(0.01)
	fixture.mechanism.advance_realtime(0.11)
	assert(spawned_count == 1 and at_request == [{"isActivated": false}])
	assert(fixture.snapshot() == {"isActivated": true} and not fixture.mechanism.object_active)
	assert(fixture.mechanism.waits.is_empty())
	assert(saved.is_empty(), "Completing Spawn does not itself request a source save")
	fixture.activate_trigger()
	assert(saved == [{"isActivated": true}])
	assert(not fixture.mechanism.object_active, "ActivateTrigger only enables the collider")
	fixture.set_active(true)
	await enter(fixture)
	assert(entered_count >= 3 and fixture.mechanism.waits.is_empty())
	fixture.queue_free()
	await frames(3)
	# Restored activation suppresses spawning while retaining entry callbacks.
	fixture = make_fixture("level6_11494", true)
	root.add_child(fixture)
	fixture.mechanism.set_process(false)
	var before := entered_count
	await enter(fixture)
	assert(entered_count > before and fixture.mechanism.object_active)
	assert(fixture.mechanism.waits.is_empty())
	fixture.queue_free()
	await frames(3)
	# Source-disabled level8 preset must wait for explicit collider activation.
	fixture = make_fixture("level8_11810")
	root.add_child(fixture)
	fixture.mechanism.set_process(false)
	before = entered_count
	await enter(fixture)
	assert(entered_count == before and fixture.mechanism.waits.is_empty())
	fixture.activate_trigger()
	await frames(4)
	assert(entered_count > before and fixture.mechanism.waits.size() == 1)
	fixture.set_active(false)
	fixture.mechanism.advance_realtime(10)
	assert(fixture.mechanism.waits.is_empty() and spawned_count == 1)
	fixture.set_active(true)
	await frames(4)
	assert(fixture.mechanism.waits.size() == 1)
	fixture.mechanism.advance_realtime(0)
	fixture.mechanism.advance_realtime(0.5)
	assert(spawned_count == 1, "Cancelled time cannot shorten a new wait")
	fixture.mechanism.advance_realtime(0.8)
	assert(spawned_count == 2)
	fixture.queue_free()
	await frames(3)
	# On-field Start disables the object without consuming its saved flag.
	fixture = make_fixture()
	fixture.settings.on_field = true
	root.add_child(fixture)
	await enter(fixture)
	assert(not fixture.mechanism.object_active and fixture.snapshot() == {"isActivated": false})
	fixture.queue_free()
	await frames(3)
	fixture = make_fixture()
	fixture.settings.delay_seconds = 0
	root.add_child(fixture)
	fixture.mechanism.set_process(false)
	await enter(fixture)
	var before_spawn := spawned_count
	assert(not fixture.mechanism.waits.is_empty())
	fixture.mechanism.advance_realtime(0)
	assert(spawned_count == before_spawn + 1, "Zero delay resumes at the first coroutine poll")
	fixture.queue_free()
	await frames(3)
	# Base once disables collision immediately, but its coroutine survives.
	fixture = make_fixture()
	fixture.settings.once = true
	root.add_child(fixture)
	fixture.mechanism.set_process(false)
	await enter(fixture)
	assert(not fixture.mechanism.collider_enabled and fixture.mechanism.waits.size() == 1)
	actor.queue_free()
	await frames(3)
	before_spawn = spawned_count
	fixture.mechanism.advance_realtime(0.01)
	fixture.mechanism.advance_realtime(1.3)
	assert(spawned_count == before_spawn + 1, "Delayed spawn does not capture the entering actor")
	fixture.queue_free()
	await frames(3)


func run() -> void:
	root.size = Vector2i(1280, 720)
	await fixture_checks()
	print("SPAWN_TRIGGER_FIXTURES_PASS")
	var room := Workshop.instantiate()
	root.add_child(room)
	await frames(10)
	assert(not room.encounter.started and room.enemies.values().all(func(e): return not e.active))
	var snapshots: Array = []
	room.get_node("SpawnTrigger").spawn_requested.connect(func(): snapshots.append(room.get_node("SpawnTrigger").snapshot()))
	key(KEY_D, true)
	await frames(65)
	key(KEY_D, false)
	assert(room.contact.activated and room.spawn_requests == 0)
	assert(room.get_node("SpawnTrigger").mechanism.waits.size() == 1)
	# Time.timeScale=0 must not stop the realtime trigger. The encounter's
	# subsequent WaitForSeconds remains paused until global time resumes.
	Engine.time_scale = 0.0
	var deadline := Time.get_ticks_msec() + 2500
	while room.spawn_requests == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	for frame in 3:
		await process_frame
	assert(room.spawn_requests == 1 and snapshots == [{"isActivated": false}])
	assert(room.enemies.values().all(func(e): return not e.active))
	assert(room.encounter.clock.state.status == "spawning")
	Engine.time_scale = 1.0
	await frames(100)
	assert(room.enemies.values().filter(func(e): return e.active).size() == 4)
	assert(room.encounter.clock.state.status == "fighting")
	if DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	room.queue_free()
	await frames(3)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(12)
	await frames(3)
	var previous: WeakRef = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(previous.get_ref() == null and gallery.exhibit.has_node("SpawnTrigger"))
	assert(not gallery.exhibit.encounter.settings.on_field and not gallery.exhibit.encounter.started)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_MONSTER_SPAWN_TRIGGER_PASS")
	quit()
