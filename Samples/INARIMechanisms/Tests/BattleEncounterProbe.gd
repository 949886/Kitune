extends SceneTree
const Workshop = preload("../Examples/BattleWorkshop.tscn")
const Encounter = preload("../Devices/BattleEncounter/BattleEncounter.tscn")
const Target = preload("../Examples/BattleTarget.gd")
const Clock = preload("../Core/Native/Runtime/InariEncounterClock.gd")
const Gallery = preload("../Examples/DeviceGallery.tscn")
const Contact = preload("../Devices/DoorContact/DoorContact.tscn")
var room: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func clock_checks() -> void:
	var model := Clock.new()
	var events: Array[String] = []
	model.arrival_requested.connect(func(_p, _m): events.append("arrival"))
	model.phase_registered.connect(func(_p, _m): events.append("register"))
	model.completed.connect(func(): events.append("complete"))
	var config := {"IsOnField": false, "PhaseChangingTime": 0.25,
		"EndTime": 0.25, "waitingTime": 0.25,
		"spawnDatas": [{"EnemyPrefab": [{"m_PathID": 1}]}, {"EnemyPrefab": [{"m_PathID": 2}]}]}
	model.configure(config, 1.2)
	assert(model.start() and not model.start())
	assert(events == ["arrival", "register"])
	model.advance(10, 10, 0)
	assert(model.state.status == "spawn_wait")
	model.advance(0, 0, 0.1)
	model.advance(10, 0, 1)
	assert(model.state.status == "spawning")
	model.advance(1.21, 1.21, 0)
	assert(model.state.status == "peaceful")
	assert(not model.defeated(2) and model.defeated(1) and not model.defeated(1))
	model.advance(0.3, 0, 0)
	assert(model.state.status == "spawn_wait" and model.state.phase == 1)
	# Old peaceful coroutine cannot make the next, still hidden wave fight.
	model.advance(0.3, 0.3, 0)
	assert(model.state.status == "spawn_wait")
	model.advance(0, 0, 1)
	model.advance(1.21, 1.21, 0)
	assert(model.defeated(2) and model.ended and not "complete" in events)
	model.advance(0.3, 0, 0)
	assert(model.state.status == "complete" and events.count("complete") == 1)
	model.advance(10, 10, 1)
	assert(events.count("complete") == 1)
	model.configure(config, 1.2, true)
	assert(not model.start() and model.ended)
	config.spawnDatas = [{"EnemyPrefab": []}]
	config.IsOnField = true
	model.configure(config, 1.2)
	model.start()
	model.advance(100, 100, 1)
	assert(not model.ended, "Empty source waves need a death event, not an invented auto-clear")


func run() -> void:
	root.size = Vector2i(1280, 720)
	clock_checks()
	await contact_checks()
	room = Workshop.instantiate()
	root.add_child(room)
	await frames(10)
	assert(room.entry.is_open() and not room.exit_door.is_open())
	assert(room.encounter.clock.state.remaining == 4)
	assert(room.enemies.values().filter(func(e): return e.active).size() == 4)
	key(KEY_D, true)
	await frames(40)
	key(KEY_D, false)
	await frames(3)
	assert(room.contact.activated and not room.entry.is_open() and room.cleanup_requests == 1)
	key(KEY_A, true)
	await frames(35)
	key(KEY_A, false)
	await frames(2)
	assert(room.player.position.x > room.entry.position.x)
	var save_events: Array = []
	room.encounter.save_requested.connect(func(record): save_events.append(record))
	for wave in room.encounter.settings.waves:
		if room.encounter.clock.state.phase == 1 and DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE").get_basename() + "-wave.png")
		for enemy_key: String in wave:
			var enemy: Node2D = room.enemies[enemy_key]
			assert(enemy.active and not enemy.dead)
			room.player.position = enemy.position + Vector2(-29, 0)
			room.player.velocity = Vector2.ZERO
			room.player.facing = 1
			await frames(2)
			key(KEY_K, true)
			await frames(2)
			key(KEY_K, false)
			await frames(14)
			assert(enemy.dead, "A real shape query and HP loss must cause each death")
			assert(not room.encounter.notify_defeated(enemy_key, enemy))
		await frames(115)
	assert(room.encounter.clock.ended and room.completion_count == 1)
	assert(save_events == [{"isEnd": true}])
	assert(room.exit_door.is_open() and room.exit_door.is_passable())
	room.player.position = Vector2(855, 400)
	key(KEY_D, true)
	await frames(40)
	key(KEY_D, false)
	assert(room.player.position.x > 945)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	room.queue_free()
	await frames(3)
	# Restoring completion hides all registered enemies without reopening doors
	# or replaying a final timeline notification.
	var restored := Encounter.instantiate()
	restored.restored_end = true
	root.add_child(restored)
	var dummy := Target.new()
	root.add_child(dummy)
	restored.bind_enemy(&"wave_1_enemy_1", dummy, dummy.set_active, dummy.set_peaceful)
	await frames(3)
	assert(not restored.started and not dummy.active)
	restored.queue_free()
	dummy.queue_free()
	await frames(3)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(11)
	await frames(3)
	var old: WeakRef = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(old.get_ref() == null and is_instance_valid(gallery.exhibit))
	assert(gallery.exhibit.entry.is_open() and not gallery.exhibit.contact.activated)
	old = weakref(gallery.exhibit)
	gallery.select_exhibit(1)
	await frames(3)
	assert(old.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_BATTLE_ENCOUNTER_PASS")
	quit()


func reenter(actor: Node2D, trigger: Node2D) -> void:
	actor.position = Vector2(-2000, -2000)
	await frames(3)
	actor.position = trigger.to_global(trigger.settings.trigger_offset)
	await frames(3)


func contact_checks() -> void:
	var actor := CharacterBody2D.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(12, 20)
	shape.shape = box
	actor.add_child(shape)
	root.add_child(actor)
	var contact := Contact.instantiate()
	contact.settings = contact.settings.duplicate(true)
	contact.settings.door_once = false
	contact.position = Vector2(3000, 3000)
	contact.rotation = PI / 2
	contact.scale = Vector2.ONE * 1.5
	contact.actor_layers = 32
	var host := {"loading": true, "eligible": true}
	contact.bind_actor(actor, func(): return host.eligible, func(): return host.loading)
	var events: Array[String] = []
	contact.contacted.connect(func(_a): events.append("door"))
	contact.outside_projectiles_cleanup_requested.connect(func(_a): events.append("cleanup"))
	actor.position = contact.to_global(contact.settings.trigger_offset)
	root.add_child(contact)
	await frames(4)
	assert(events.is_empty())
	host.loading = false
	await frames(4)
	assert(events.is_empty(), "Loading rejection must not become a Stay activation")
	await reenter(actor, contact)
	assert(events == ["door", "cleanup"])
	await reenter(actor, contact)
	assert(events.size() == 4)
	host.eligible = false
	await reenter(actor, contact)
	assert(events.size() == 4)
	host.eligible = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	await reenter(actor, contact)
	assert(events.size() == 4)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 4
	await reenter(actor, contact)
	assert(events.size() == 4)
	contact.queue_free()
	await frames(3)
	actor.collision_layer = 32
	var restored := Contact.instantiate()
	restored.settings = restored.settings.duplicate(true)
	restored.settings.restored_activated = true
	restored.actor_layers = 32
	restored.bind_actor(actor)
	restored.position = actor.position
	root.add_child(restored)
	await reenter(actor, restored)
	assert(not restored.area.active and restored.activated)
	restored.activate()
	await frames(4)
	assert(restored.activated and not restored.area.active)
	restored.queue_free()
	actor.queue_free()
	await frames(3)
