extends SceneTree
## Real player inputs against native enemy hurtboxes. Enemy locomotion is frozen
## during damage checks to isolate phase/door behavior from stochastic tactics;
## no death signal, wave completion or door notification is fabricated.
var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func press(action: String, count: int) -> void:
	Input.action_press(lab.player.input_action(action))
	await frames(count)
	Input.action_release(lab.player.input_action(action))
	await frames(2)


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2, 3)
	await frames(30)
	var battle: Node = lab.stage.machinery.battle
	var state: Dictionary = battle.spawners[11791]
	var entry: Node = battle.doors[11863]
	var exit_door: Node = battle.doors[11786]
	assert(state.phase == 0 and state.remaining == 4)
	assert(entry.is_open and entry.invisible.collision_layer == 0)
	assert(not exit_door.is_open and exit_door.invisible.collision_layer != 0)
	assert(lab.stage.enemies.filter(func(e): return e.spawn_active).size() == 4)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	await press("right", 36)
	assert(lab.player.position.x > 3300 and not entry.is_open and entry.hard)
	assert(battle.contacts[0].get_meta("consumed"))
	await press("left", 45)
	assert(lab.player.position.x > entry.invisible.position.x)
	# A death/retry resets the consumed gate and the full encounter.
	var previous: WeakRef = weakref(battle)
	lab.respawn_player()
	await frames(30)
	assert(previous.get_ref() == null)
	battle = lab.stage.machinery.battle
	state = battle.spawners[11791]
	exit_door = battle.doors[11786]
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	await press("right", 36)
	for wave in 2:
		assert(state.phase == wave and state.remaining == 4)
		for ref: Dictionary in state.source.spawnDatas[wave].EnemyPrefab:
			var enemy: Node = battle.enemies[int(ref.m_PathID)]
			assert(enemy.spawn_active and not enemy.dead)
			for attempt in 12:
				if enemy.dead:
					break
				lab.player.position = (
					enemy.position
					+ Vector2(
						-50,
						float(enemy.data.bounds_offset[1]) + float(enemy.data.bounds_size[1]) / 2.0
					)
				)
				lab.player.velocity = Vector2.ZERO
				lab.player.facing = 1.0
				await frames(20)
				await press("heavy_attack", 1)
				await frames(55)
			assert(enemy.dead, "Heavy attacks must defeat the source enemy through real hitboxes")
		assert(not exit_door.is_open or wave == 1)
		if wave == 0:
			# Allow source phase delay, 1.2s spawn sequence and peaceful wait.
			var captured := false
			for frame in 120:
				await frames(1)
				for enemy: Node in lab.stage.enemies:
					enemy.set_physics_process(false)
				var arrivals: Node2D = battle.arrival_effects
				if arrivals.get_child_count() == 4 and not captured:
					var effect: Node2D = arrivals.get_child(0)
					if effect.elapsed > 0.7 and effect.elapsed < 1.0:
						assert(arrivals.batches_started == 1 and not effect.play_audio)
						captured = true
						if DisplayServer.get_name() != "headless":
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://tmp/art-direction/native-arrivals.png")
			assert(captured, "Real enemy deaths must create the original arrival prefabs")
			assert(state.status == "fighting")
	await frames(90)
	assert(state.status == "complete" and exit_door.is_open and not exit_door.hard)
	assert(exit_door.invisible.collision_layer == 0)
	lab.player.position = Vector2(3880, 3935)
	lab.player.velocity = Vector2.ZERO
	await press("right", 24)
	assert(lab.player.position.x > 3990 and lab.completed and not lab.player.dead)
	if DisplayServer.get_name() != "headless":
		lab.completion.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/battle-exit-verified.png")
	# A separate smoke run leaves every AI enabled, exercising the new scene's
	# bow/rifle bindings, bomb logic and source-enabled alarm branch.
	var old_arrivals: WeakRef = weakref(battle.arrival_effects)
	lab.load_level(2, 3)
	await press("right", 40)
	assert(old_arrivals.get_ref() == null)
	var fought := false
	for frame in 500:
		await frames(1)
		for enemy: Node in lab.stage.enemies:
			fought = (
				fought
				or (
					enemy.spawn_active
					and enemy.ranged_combat.state not in ["idle", "leash_ready", "leash_back"]
				)
			)
	assert(fought)
	lab.queue_free()
	await frames(2)
	print("BATTLE_ROOM_PROBE_PASS")
	quit()
