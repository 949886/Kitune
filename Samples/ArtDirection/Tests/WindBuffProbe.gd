extends SceneTree
## Source zones, deferred spawn, sampled decay, actual velocity and kill renewal.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	player.stamina_feedback.set_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	assert(lab.stage.wind_triggers.size() == 2)
	for zone: Node in lab.stage.wind_triggers:
		zone.set_physics_process(false)
		assert(zone.get_child(0).shape.size == Vector2(128, 128))
	var trigger: Node = lab.stage.wind_triggers[1]
	var buff: RefCounted = player.wind_buff
	player.action_state = "spawn"
	player.stamina = 1.0
	player.position = trigger.global_position - player.body_shape.position
	player.force_update_transform()
	trigger.force_update_transform()
	for frame in 5:
		await physics_frame
		await process_frame
	assert(
		(
			trigger.stamina_once
			and is_equal_approx(player.stamina, minf(46.0, player.combat.MaxStamina))
		)
	)
	assert(trigger.pending_player.get_ref() == player and buff.level == 0)
	trigger.advance(20.0)
	assert(buff.level == 0 and trigger.cooldown_until == 0.0)
	player.action_state = ""
	trigger.advance(0.01)
	assert(buff.level == 1 and buff.pending and buff.extra_speed == 0.0)
	assert(is_equal_approx(trigger.cooldown_until - trigger.clock, 5.0))
	buff.advance(0.5)
	assert(buff.extra_speed == 4.0 and buff.ratio == 0.0 and buff.elapsed == 0.5)
	# Only target horizontal movement receives the buff. The original braking
	# source, jump velocity, climb speeds and curve continuation stay independent.
	player.position = Vector2(-20000, -20000)
	await physics_frame
	await process_frame
	var before: Vector2 = player.position
	player._move_normally(1.0 / 60.0, 1.0, 0.0)
	var expected: float = (player.physics.moveSpeed + 4.0) * player.units
	assert(absf(player.velocity.x - expected) < 0.001)
	assert(absf(player.position.x - before.x - expected / 60.0) < 0.01)
	for tick in 5:
		buff.advance(0.5)
	buff.advance(0.5)
	assert(buff.ratio == 0.5 and buff.extra_speed == 2.0)
	var elapsed: float = buff.elapsed
	player.on_source_time_scale(0.0)
	buff.advance(2.0)
	assert(buff.elapsed == elapsed and buff.extra_speed == 2.0)
	player.on_source_time_scale(0.3)
	buff.advance(1.0)
	assert(absf(buff.elapsed - elapsed - 0.3) < 0.00001)
	player.on_source_time_scale(1.0)
	# Enemy death reaches the real player callback and upgrades an active level.
	var enemy: Node = lab.stage.enemies[0]
	enemy.receive_study_hit(
		{"Damage": enemy.health + 1.0, "source_actor": player, "kind": "probe"}, 0.0
	)
	assert(enemy.dead and buff.level == 2 and buff.previous_level == 1)
	assert(buff.duration == 12.0 and buff.extra_speed == 0.0)
	buff.advance(0.5)
	assert(buff.extra_speed == 6.0)
	buff.on_player_kill()
	assert(buff.level == 2 and buff.previous_level == 2 and buff.elapsed == 0.0)
	for tick in 24:
		buff.advance(0.5)
	assert(buff.active and buff.elapsed == 12.0 and buff.extra_speed > 0.0)
	buff.advance(0.5)
	assert(not buff.active and buff.level == 0 and buff.extra_speed == 0.0)
	assert(buff.previous_level == 2)
	buff.on_player_kill()
	assert(buff.level == 0 and not buff.active, "A kill must not grant a first wind level")
	# Cooldown prevents refresh; stamina is granted only once per zone instance.
	var stamina: float = player.stamina
	trigger.enter(player)
	assert(buff.level == 0 and player.stamina == stamina)
	trigger.advance(5.01)
	trigger.enter(player)
	assert(buff.level == 1 and player.stamina == stamina)
	var second: Node = lab.stage.wind_triggers[0]
	player.story_mode = true
	player.damage.reset()
	player.damage.health = 1
	player.stamina = 1.0
	second.enter(player)
	assert(
		(
			player.damage.health == player.damage.maximum
			and player.stamina == minf(46.0, player.combat.MaxStamina)
		)
	)
	assert(second.stamina_once and buff.level == 1)
	player.respawn()
	assert(buff.level == 0 and buff.extra_speed == 0.0 and not buff.active)
	var old: WeakRef = weakref(trigger)
	lab.load_level(1)
	await process_frame
	assert(old.get_ref() == null and lab.stage.wind_triggers.is_empty())
	lab.queue_free()
	await process_frame
	print("WIND_BUFF_PASS")
	quit()
