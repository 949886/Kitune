extends SceneTree
## Deterministic lifecycle boundaries plus real physical attacks in the copied
## workshop. Timers never substitute for the workshop's actual death callbacks.
const Device = preload("../Devices/RepeatingSpawner/RepeatingSpawner.tscn")
const Workshop = preload("../Examples/RepeatWorkshop.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")

class Actor extends Node2D:
	var idle_count := 0
	var colors: Array[Color] = []
	func idle() -> void:
		idle_count += 1
	func tint(color: Color) -> void:
		colors.append(color)

var created: Array[Node2D] = []
var events: Array[String] = []


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


func factory(point: Vector2) -> Dictionary:
	var actor := Actor.new()
	root.add_child(actor)
	actor.global_position = point
	created.append(actor)
	events.append("factory")
	return {"actor": actor, "idle": actor.idle, "tint": actor.tint}


func fixtures() -> void:
	var device := Device.instantiate()
	device.settings = device.settings.duplicate(true)
	assert(device.settings.wait_seconds == 8.0 and is_equal_approx(device.settings.fade_seconds, 0.2))
	assert(device.settings.kinds == {"enemy_1": "EnemyBombMan"})
	device.settings.placements = {"enemy_1": Vector2(20, -30), "enemy_2": Vector2(-25, 5)}
	device.settings.kinds["enemy_2"] = "EnemyBowMan"
	device.settings.wait_seconds = 0.1
	device.position = Vector2(320, 240)
	device.rotation = PI / 2
	device.scale = Vector2(0.7, 1.3)
	root.add_child(device)
	device.set_process(false)
	device.register_factory("EnemyBombMan", factory)
	device.register_factory("EnemyBowMan", factory)
	device.flags_requested.connect(func(_actor, repeated, loaded):
		assert(repeated and not loaded)
		events.append("flags"))
	device.member_registered.connect(func(_key, _actor): events.append("registered"))
	device.member_unregistered.connect(func(_key, _actor): events.append("unregistered"))
	device.persistence_remove_requested.connect(func(_actor): events.append("persistence"))
	var initial := Actor.new()
	var other := Actor.new()
	root.add_child(initial)
	root.add_child(other)
	device.bind_enemy("enemy_1", initial, initial.idle, initial.tint)
	device.bind_enemy("enemy_2", other, other.idle, other.tint)
	assert(events == ["flags", "flags"] and initial.colors.is_empty())
	assert(not device.notify_defeated("enemy_1", other))
	assert(device.notify_defeated("enemy_1", initial))
	assert(not device.notify_defeated("enemy_1", initial))
	assert(events.slice(2) == ["unregistered", "persistence"])
	device.advance(1, 0)
	assert(created.is_empty(), "Realtime deadline starts on first poll")
	device.advance(0.09, 0)
	assert(created.is_empty())
	device.advance(0.02, 0)
	assert(created.size() == 1)
	var first: Actor = created[0]
	assert(first.global_position.is_equal_approx(device.to_global(Vector2(20, -30))))
	assert(events.slice(4) == ["factory", "flags", "registered"])
	assert(first.idle_count == 1 and first.colors[-1] == Color(1, 1, 1, 0))
	device.advance(1, 0)
	assert(first.idle_count == 2 and first.colors[-1].a == 0)
	device.advance(0.1, 0.1)
	device.advance(0.1, 0.1)
	assert(is_equal_approx(first.colors[-1].a, 0.5))
	device.advance(0.001, 0.001)
	device.advance(0, 0)
	assert(first.colors[-1] == Color.WHITE and device.fading.is_empty())
	# Independent members and generations; waitTime is sampled at each death.
	assert(device.notify_defeated("enemy_1", first))
	device.settings.wait_seconds = 0.4
	assert(device.notify_defeated("enemy_2", other))
	device.advance(0, 0)
	device.advance(0.11, 0)
	assert(created.size() == 2 and device.waiting.size() == 1)
	assert(not device.notify_defeated("enemy_1", first))
	device.advance(0.3, 0)
	assert(created.size() == 3 and device.waiting.is_empty())
	var third: Actor = created[2]
	assert(third.global_position.is_equal_approx(device.to_global(Vector2(-25, 5))))
	# Death during alpha keeps the old fade on its captured actor. Runtime
	# alphaTime changes remain live, as in the C# loop, and zero skips division.
	assert(device.notify_defeated("enemy_2", third))
	device.settings.fade_seconds = 0
	device.advance(0, 0)
	assert(third.colors[-1] == Color.WHITE and device.fading.is_empty())
	device.before_scene_changed()
	await frames(2)
	assert(is_instance_valid(initial) and is_instance_valid(other))
	assert(created.all(func(actor): return not is_instance_valid(actor)))
	device.advance(0.5, 0)
	assert(created.size() == 4, "BeforeSceneChanged does not itself cancel the wait")
	assert(created[-1].colors[-1] == Color.WHITE)
	# Closing the owner cancels pending waits/fades, without inventing deaths.
	assert(device.notify_defeated("enemy_2", created[-1]))
	device.set_active(false)
	device.advance(100, 100)
	device.set_active(true)
	device.advance(100, 100)
	assert(created.size() == 4 and device.waiting.is_empty())
	var surviving: WeakRef = weakref(created[-1])
	device.queue_free()
	await frames(2)
	assert(surviving.get_ref() == null)
	initial.queue_free()
	other.queue_free()
	await frames(2)
	# Disabling the source object leaves its external death listener in place;
	# it unregisters the actor but cannot start a coroutine while inactive.
	device = Device.instantiate()
	root.add_child(device)
	initial = Actor.new()
	root.add_child(initial)
	device.bind_enemy("enemy_1", initial, initial.idle, initial.tint)
	device.set_active(false)
	assert(device.notify_defeated("enemy_1", initial))
	assert(device.bindings.is_empty() and device.waiting.is_empty())
	device.queue_free()
	initial.queue_free()
	await frames(2)
	# A zero delay creates on first poll. A missing host factory has an explicit
	# failure notification rather than silently counting an enemy as alive.
	device = Device.instantiate()
	device.settings = device.settings.duplicate(true)
	device.settings.wait_seconds = 0
	root.add_child(device)
	device.set_process(false)
	initial = Actor.new()
	root.add_child(initial)
	device.bind_enemy("enemy_1", initial, initial.idle, initial.tint)
	var failed: Array = []
	device.replacement_failed.connect(func(id): failed.append(id))
	device.notify_defeated("enemy_1", initial)
	device.advance(0, 0)
	assert(failed == [&"enemy_1"] and device.waiting.is_empty())
	device.queue_free()
	initial.queue_free()
	await frames(2)
	# Exercise the real process clock at time_scale=0 with a short host preset.
	device = Device.instantiate()
	device.settings = device.settings.duplicate(true)
	device.settings.wait_seconds = 0.05
	root.add_child(device)
	device.register_factory("EnemyBombMan", factory)
	initial = Actor.new()
	root.add_child(initial)
	device.bind_enemy("enemy_1", initial, initial.idle, initial.tint)
	device.notify_defeated("enemy_1", initial)
	Engine.time_scale = 0
	var count := created.size()
	var deadline := Time.get_ticks_msec() + 1500
	while created.size() == count and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(created.size() == count + 1)
	for frame in 3:
		await process_frame
	assert(created[-1].colors[-1].a == 0)
	Engine.time_scale = 1
	await frames(20)
	assert(created[-1].colors[-1] == Color.WHITE)
	device.queue_free()
	initial.queue_free()
	await frames(2)
	print("REPEATING_LIFECYCLE_PASS")


func run() -> void:
	root.size = Vector2i(1280, 720)
	await fixtures()
	var room := Workshop.instantiate()
	root.add_child(room)
	await frames(5)
	var original: Node2D = room.targets["enemy_1"]
	assert(original.repeated and not original.loaded and original.health == 2)
	key(KEY_D, true)
	await frames(32)
	key(KEY_D, false)
	key(KEY_K, true)
	await frames(2)
	key(KEY_K, false)
	assert(original.dead and room.spawner.waiting.size() == 1)
	assert(room.removed_persistence == 1)
	await frames(470)
	assert(room.replacements == 0)
	await frames(35)
	assert(room.replacements == 1)
	var replacement: Node2D = room.targets["enemy_1"]
	assert(replacement != original and replacement.health == 2 and replacement.modulate == Color.WHITE)
	key(KEY_K, true)
	await frames(2)
	key(KEY_K, false)
	assert(replacement.dead and room.removed_persistence == 2)
	await frames(510)
	assert(room.replacements == 2 and room.targets["enemy_1"].health == 2)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	room.queue_free()
	await frames(3)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(13)
	await frames(3)
	var old: WeakRef = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(old.get_ref() == null and gallery.exhibit.has_node("Spawner"))
	assert(gallery.exhibit.replacements == 0)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_REPEATING_SPAWNER_PASS")
	quit()
