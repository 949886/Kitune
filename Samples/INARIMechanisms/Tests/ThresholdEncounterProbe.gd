extends SceneTree
const Workshop = preload("../Examples/ThresholdWorkshop.tscn")
const Encounter = preload("../Devices/BattleEncounter/ThresholdEncounter.tscn")
const Clock = preload("../Core/Native/Runtime/InariEncounterClock.gd")
const Gallery = preload("../Examples/DeviceGallery.tscn")


func _initialize() -> void:
	create_timer(50).timeout.connect(func(): quit(2))
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


func clock_checks() -> void:
	var config := {"IsOnField": true, "PhaseChangingTime": 0.25, "EndTime": 0.5, "waitingTime": 0.25,
		"selectedEnemy": [{"enemyStateMachine": {"m_PathID": 1}, "hpRatio": 0.75}],
		"spawnDatas": [{"EnemyPrefab": [{"m_PathID": 1}, {"m_PathID": 2}]},
			{"EnemyPrefab": [{"m_PathID": 3}, {"m_PathID": 4}]}]}
	var model := Clock.new()
	model.configure(config, 1.2)
	assert(not model.damaged(1, 0.5))
	assert(model.start())
	assert(not model.damaged(1, 0.7501) and not model.damaged(1, NAN))
	assert(not model.damaged(3, 0) and not model.defeated(3))
	assert(model.damaged(1, 0.75))
	assert(model.state.phase == 1 and model.state.remaining == 4 and model.counted.is_empty())
	assert(not model.damaged(1, 0.5), "One-shot threshold listener must stay removed")
	assert(model.defeated(2) and model.state.remaining == 3)
	assert(not model.defeated(2))
	model.advance(0.3, 0, 0)
	assert(model.state.status == "spawn_wait" and model.state.remaining == 3)
	assert(model.defeated(1) and model.state.remaining == 2)
	model.advance(0, 0, 1)
	model.advance(1.21, 1.21, 1)
	assert(model.defeated(3) and not model.ended)
	assert(model.defeated(4) and model.ended)
	model.advance(0.6, 0, 0)
	assert(model.state.status == "complete")
	# A lethal hit delivers damage before death. Carry then subtract that same
	# enemy during the realtime delay; do not count it twice or skip the wave.
	model.configure(config, 1.2)
	model.start()
	assert(model.damaged(1, 0) and model.defeated(1))
	assert(model.state.phase == 1 and model.state.remaining == 3)
	model.advance(0.3, 0, 1)
	assert(model.state.remaining == 3)
	# Source allows a final-wave threshold to finish with surviving actors.
	# Keep this source edge instead of silently inventing a different gate.
	config.spawnDatas.resize(1)
	model.configure(config, 1.2)
	model.start()
	assert(model.damaged(1, 0.75) and model.ended and model.counted.is_empty())
	assert(not model.defeated(1) and not model.damaged(1, 0))
	model.configure(config, 1.2, true)
	assert(not model.start() and not model.damaged(1, 0))
	print("THRESHOLD_CLOCK_PASS")


func hit(room: Node, actor: Node2D, code: Key) -> void:
	room.player.position = actor.position + Vector2(-29, 0)
	room.player.velocity = Vector2.ZERO
	room.player.facing = 1
	await frames(2)
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(14)


func run() -> void:
	root.size = Vector2i(1280, 720)
	clock_checks()
	var source := Encounter.instantiate()
	assert(source.settings.waves.map(func(w): return w.size()) == [2, 3, 1, 2])
	assert(source.settings.thresholds == {"wave_3_enemy_1": 0.75})
	assert(not source.settings.on_field and source.settings.end_delay == 0.5)
	source.free()
	var room := Workshop.instantiate()
	root.add_child(room)
	await frames(6)
	assert(not room.encounter.started)
	var saves: Array = []
	room.encounter.save_requested.connect(func(record): saves.append(record))
	key(KEY_D, true)
	await frames(40)
	key(KEY_D, false)
	assert(room.contact.activated and room.encounter.started)
	await frames(105)
	for wave in 2:
		assert(room.encounter.clock.state.phase == wave)
		for member: String in room.encounter.settings.waves[wave]:
			var enemy: Node2D = room.enemies[member]
			assert(enemy.active)
			await hit(room, enemy, KEY_K)
			assert(enemy.dead)
		await frames(115)
	var selected: Node2D = room.enemies.wave_3_enemy_1
	assert(room.encounter.clock.state.phase == 2 and selected.health == 4)
	assert(not room.encounter.notify_damaged(&"wave_3_enemy_1", room.enemies.wave_1_enemy_1, 0))
	await hit(room, selected, KEY_J)
	assert(selected.health == 3 and selected.active and not selected.dead)
	assert(room.encounter.clock.state.phase == 3 and room.encounter.clock.state.remaining == 3)
	assert(saves.is_empty() and not room.exit_door.is_open())
	assert(not room.encounter.notify_damaged(&"wave_3_enemy_1", selected, 0.75))
	await frames(115)
	assert(room.enemies.values().filter(func(e): return e.active).size() == 3)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	for member: String in room.encounter.settings.waves[3]:
		await hit(room, room.enemies[member], KEY_K)
		assert(room.enemies[member].dead)
	assert(room.encounter.clock.state.remaining == 1 and not room.encounter.clock.ended)
	assert(selected.active and not room.exit_door.is_open())
	await hit(room, selected, KEY_K)
	assert(selected.health == 1 and not room.encounter.clock.ended)
	await hit(room, selected, KEY_J)
	assert(selected.dead and room.encounter.clock.ended and saves == [{"isEnd": true}])
	await frames(110)
	assert(room.completion_count == 1 and room.exit_door.is_passable())
	room.queue_free()
	await frames(3)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(14)
	await frames(3)
	var old: WeakRef = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(old.get_ref() == null and gallery.exhibit.encounter.settings.thresholds.size() == 1)
	assert(not gallery.exhibit.encounter.started)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_THRESHOLD_ENCOUNTER_PASS")
	quit()
