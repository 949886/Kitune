extends SceneTree
## Source air-aim gates, fractional movement, independent clocks and recovery.


func _initialize() -> void:
	call_deferred("run")


func stick(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
	player.position = Vector2(-20000, -20000)
	player.velocity = Vector2.ZERO
	player.action_state = ""
	player.sprite.play("fall", true)
	await physics_frame
	player.move_and_slide()
	assert(not player.is_on_floor())
	stick(0.8)
	await process_frame
	player.aim_time.update()
	var scale: float = player.aim_time.settings.air_scale
	assert(is_equal_approx(scale, 0.3))
	print(
		"AIM_GATE ",
		player.targeting.using_gamepad,
		" stick=",
		player.targeting.stick,
		" type=",
		player.aim_time.collision_type(),
		" climb=",
		player.climbing,
		" scale=",
		player.source_time_scale,
		" stage=",
		lab.stage.combat_clock.scale_value
	)
	assert(player.source_time_scale == scale and lab.stage.combat_clock.scale_value == scale)
	assert(Engine.time_scale == 1.0)
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press(player.input_action("right"))
	for frame in 12:
		var before: Vector2 = player.position
		var old_velocity: Vector2 = player.velocity
		var old_clock: float = player.clock
		var old_animation: float = player.sprite.elapsed
		var clip_speed: float = player.sprite.clips[player.sprite.clip_name].get("speed", 1.0)
		var expected_y: float = old_velocity.y + player.gravity * delta * scale
		player._physics_process(delta)
		var movement: Vector2 = player.position - before
		assert(
			(
				absf(movement.x - float(player.physics.moveSpeed) * player.units * delta * scale)
				< 0.003
			)
		)
		assert(absf(movement.y - expected_y * delta * scale) < 0.003)
		assert(absf(player.velocity.y - expected_y) < 0.001)
		assert(is_equal_approx(player.sprite.elapsed - old_animation, delta * scale * clip_speed))
		assert(
			is_equal_approx(player.clock - old_clock, delta),
			"Input deadlines retain the real clock"
		)
	Input.action_release(player.input_action("right"))
	# Enemy normal movement uses the source's distinct return-value equation.
	var enemy: Node = lab.stage.enemies[0]
	enemy.position = player.position + Vector2(1000, -1000)
	enemy.velocity = Vector2(0, 12)
	var before: Vector2 = enemy.position
	var accelerated: float = 12.0 + float(enemy.data.gravity) * enemy.PIXELS_PER_UNIT * delta
	enemy._physics_process(delta)
	assert(absf(enemy.position.y - before.y - accelerated * delta * scale) < 0.003)
	assert(absf(enemy.velocity.y - accelerated * scale * scale) < 0.001)
	assert(enemy.source_time_scale == scale)
	for visual: Node in enemy.visuals.values():
		assert(visual.get_meta("source_animation_scale") == scale)
	var effect: Node = lab.stage.spawn_effect("Eff_RifleMan_Shot", player.position, 0.0)
	var unscaled: Node = lab.stage.spawn_effect(
		"Eff_RifleMan_Shot", player.position, 0.0, false, null, false
	)
	assert(effect.emitters[0].time_scale_override == scale)
	assert(unscaled.emitters[0].time_scale_override == -1.0)
	# Native flags distinguish airborne dash/attack motion from Air/Airing.
	for state in ["dash", "weakpoint_execution", "heavy_attack", "hit"]:
		player.action_state = state
		player.aim_time.update()
		assert(player.source_time_scale == 1.0)
	for state in ["", "throw", "attack_air"]:
		player.action_state = state
		player.aim_time.update()
		assert(player.source_time_scale == scale)
	player.action_state = "multi_throw"
	lab.stage.combat_clock.set_scale(0.5)
	player.aim_time.update()
	assert(player.source_time_scale == 0.5)
	player.action_state = ""
	player.climbing = true
	player.aim_time.update()
	assert(player.source_time_scale == 1.0)
	player.climbing = false
	player.ceiling_hang = true
	player.aim_time.update()
	assert(player.source_time_scale == 1.0)
	player.ceiling_hang = false
	player._start_motion(10.0, 0.5, player.physics.dashPhysicsCurve, "Hit")
	player.aim_time.update()
	assert(player.source_time_scale == 1.0, "Hit-to-Idle retains its movement flags")
	player.path_time = player.path_duration
	player.aim_time.update()
	assert(player.source_time_scale == scale)
	lab.stage.combat_clock.stop_frames(10, delta)
	player.aim_time.update()
	assert(player.source_time_scale == 0.0, "Aiming cannot cancel an active hit-stop")
	lab.stage.combat_clock.reset()
	stick(float(player.targeting.settings.right_stick_deadzone))
	await process_frame
	player.aim_time.update()
	assert(player.source_time_scale == 1.0)
	stick(0.8)
	await process_frame
	player.aim_time.update()
	# Device switching only resets the snap holder in this build; it does not
	# issue SetTimeScale(1). Preserve the scale until an actual reset path runs.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	player.targeting.input_event(mouse)
	player.aim_time.update()
	assert(player.source_time_scale == scale)
	stick(0.8)
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(400, 10)
	shape.shape = rectangle
	floor_body.add_child(shape)
	floor_body.position = player.position + Vector2(0, 5)
	lab.stage.add_child(floor_body)
	await physics_frame
	player.velocity = Vector2(0, 10)
	player.move_source_velocity()
	assert(player.is_on_floor())
	player.aim_time.update()
	assert(player.source_time_scale == 1.0, "Landing restores full speed with the stick held")
	lab.stage.combat_clock.set_scale(scale)
	player.die(true)
	assert(player.source_time_scale == 1.0 and lab.stage.combat_clock.scale_value == 1.0)
	player.respawn()
	assert(player.source_time_scale == 1.0)
	lab.load_level(1)
	await process_frame
	assert(lab.stage.combat_clock.scale_value == 1.0 and lab.player.source_time_scale == 1.0)
	lab.queue_free()
	await process_frame
	print("AIM_TIME_PASS")
	quit()
