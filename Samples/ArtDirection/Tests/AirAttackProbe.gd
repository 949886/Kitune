extends SceneTree
## JumpAttack input, separate visual/collision facing, exit offset and handoffs.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const STEP := 1.0 / 60.0


class Enemy:
	extends StaticBody2D

	func player_contact_info() -> Dictionary:
		return {"center": global_position, "run_away": false}


var player: CharacterBody2D
var terrain := Node2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(terrain)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	var source: Dictionary = player.air_attack.settings
	assert(source.exit_distance == 0.1 and source.airborne_exit_wait_updates == 1)
	assert(source.state_flags == ["Jump", "JumpAttack"])
	for value: String in source.source_sha256.values():
		assert(value.length() == 64)
	await _entry_and_movement()
	await _exit_matrix()
	await _collisions()
	await _natural_finish()
	await _handoffs()
	await _weak_handoff()
	_set_input(Vector2.ZERO)
	player.queue_free()
	terrain.queue_free()
	await process_frame
	print("AIR_ATTACK_PASS")
	quit()


func _flush() -> void:
	await physics_frame
	await process_frame


func _set_input(direction: Vector2) -> void:
	for name in ["left", "right", "up", "down"]:
		Input.action_release(player.input_action(name))
	if direction.x != 0:
		Input.action_press(player.input_action("right" if direction.x > 0 else "left"))
	if direction.y != 0:
		Input.action_press(player.input_action("down" if direction.y > 0 else "up"))
	player.movement_input.read_direction()


func _reset(mouse_side := 1.0) -> void:
	_set_input(Vector2.ZERO)
	player.action_state = ""
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.source_time_scale = 1.0
	player.position = Vector2(0, -10000)
	player.velocity = Vector2.DOWN
	player.move_source_velocity()
	# Move the actor around the actual viewport mouse coordinate. No OS pointer
	# warping or synthetic replacement of the runtime mouse query is required.
	player.position = Vector2(player.get_global_mouse_position().x - mouse_side * 100, 0)
	player.velocity = Vector2.ZERO
	player.facing = 1.0
	player.targeting.using_gamepad = false
	player.climbing = false
	player.ceiling_hang = false
	player.wall_jump_time = 0
	player.path_time = player.path_duration
	player.can_air_jump = true
	player.can_air_attack = true
	player.dead = false
	player.body_shape.disabled = false
	player.story_mode = true
	player.damage.reset()
	player.checkpoint = player.position


func _entry_and_movement() -> void:
	for gamepad in [false, true]:
		for mouse_side: float in [-1.0, 1.0]:
			for old_face: float in [-1.0, 1.0]:
				await _reset(mouse_side)
				player.targeting.using_gamepad = gamepad
				player.facing = old_face
				player.velocity = Vector2(123, 78)
				player.curve_time = 0.42
				player.drop_time = 0.2
				player.collision_mask &= ~Collision.ONE_WAY
				var voice: int = player.audio.next_voice
				player._start_attack(0, true)
				var expected_face := old_face if gamepad else mouse_side
				assert(player.facing == expected_face and player.sprite.facing == expected_face)
				assert(player.air_attack.entry_facing == old_face)
				assert(player.velocity == Vector2(123, -240) and player.curve_time == 0.42)
				assert(
					(
						player.path_collision_type == "Airing"
						and player.path_time == player.path_duration
					)
				)
				assert(not player.can_air_attack and player.sprite.clip_name == "jump_attack")
				assert(player.drop_time == 0 and player.collision_mask & Collision.ONE_WAY)
				assert(player.audio.next_voice == (voice + 1) % player.audio.voice_count)
				voice = player.audio.next_voice
				_set_input(Vector2(-expected_face, 0))
				var before := player.position
				player._physics_process(STEP)
				assert(absf(player.position.x - before.x + expected_face * 336 * STEP) < 0.001)
				assert(player.facing == -expected_face)
				assert(
					player.sprite.facing == expected_face and player.sprite.scale.x == expected_face
				)
				player.sprite.elapsed = (
					float(player.attack_info.AttackCheckInfo.AttackCheckStartFrame) / 60.0 + 0.001
				)
				player._finish_action()
				assert(
					player.hit_emitted and player.audio.next_voice == voice,
					"Air hit must not replay the entry sound"
				)
	for state in ["attack", "heavy_attack", "spawn"]:
		await _reset()
		player.action_state = state
		player._move_normally(STEP, 1, 0)
		assert(player.velocity.x == 0, "Ground attack movement lock changed")
	for scale: float in [0.25, 0.0]:
		await _reset()
		player._start_attack(0, true)
		_set_input(Vector2.RIGHT)
		player.source_time_scale = scale
		var before := player.position
		player._physics_process(STEP)
		assert(absf(player.position.x - before.x - 336 * STEP * scale) < 0.001)
	print("AIR_ATTACK_MOVEMENT_PASS")


func _exit_matrix() -> void:
	for old_face: float in [-1.0, 1.0]:
		for current_face: float in [-1.0, 1.0]:
			for mouse_side: float in [-1.0, 1.0]:
				for input in [
					Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2(-1, -1), Vector2(1, 1)
				]:
					await _reset(mouse_side)
					player.targeting.using_gamepad = true
					player.facing = old_face
					player._start_attack(0, true)
					player.facing = current_face
					player.velocity = Vector2(33, -77)
					_set_input(input)
					var expected_face := current_face
					if input in [Vector2.LEFT, Vector2.RIGHT] and mouse_side != input.x:
						expected_face = -old_face
					var offset := -old_face * 1.6 if expected_face == old_face else 0.0
					var before := player.position
					player.action_state = ""
					assert(absf(player.position.x - before.x - offset) < 0.001)
					assert(
						player.facing == expected_face and player.sprite.scale.x == expected_face
					)
					assert(player.velocity == Vector2(33, -77) and not player.air_attack.active)
					player.air_attack.leave()
					assert(absf(player.position.x - before.x - offset) < 0.001, "Exit ran twice")
	for scale: float in [0.25, 0.0]:
		await _reset()
		player.targeting.using_gamepad = true
		player._start_attack(0, true)
		player.source_time_scale = scale
		var before := player.position
		player.action_state = ""
		assert(
			absf(player.position.x - before.x + 1.6) < 0.001,
			"Explicit exit offset must not be scaled by dt or TimeScale"
		)
	await _reset()
	player.position.x = player.get_global_mouse_position().x
	player._start_attack(0, true)
	assert(player.facing == 1, "Mathf.Sign(0) must face right")
	print("AIR_ATTACK_EXIT_MATRIX_PASS")


func _body(body: CollisionObject2D, offset: Vector2, size: Vector2, layer: int) -> void:
	body.collision_layer = layer
	body.position = player.body_shape.global_position + offset
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	terrain.add_child(body)


func _collisions() -> void:
	await _reset()
	_body(StaticBody2D.new(), Vector2(-12, 0), Vector2(10, 200), Collision.SOLID)
	await _flush()
	player.targeting.using_gamepad = true
	player._start_attack(0, true)
	var before := player.position
	player.action_state = ""
	assert(player.position.x < before.x and player.position.x > before.x - 1.0)
	assert(player.is_on_wall())
	for scale: float in [1.0, 0.25]:
		await _reset()
		_body(Enemy.new(), Vector2(-16, 0), Vector2(80, 60), Collision.ENEMY_TARGET)
		await _flush()
		player.targeting.using_gamepad = true
		player._start_attack(0, true)
		player.source_time_scale = scale
		before = player.position
		var velocity := player.velocity
		player.action_state = ""
		assert(absf(player.position.x - before.x - (-1.6 + 1.6 * scale)) < 0.001)
		assert(player.velocity == velocity, "Exit ignores Move's returned separation velocity")


func _natural_finish() -> void:
	await _reset()
	player.targeting.using_gamepad = true
	player._start_attack(0, true)
	player.hit_emitted = true
	player.sprite.elapsed = float(player.sprite.clips.jump_attack.length)
	player._finish_action()
	assert(player.action_state == "attack_air")
	player._finish_action()
	assert(player.action_state == "attack_air", "Two checks in one update are not two updates")
	await _flush()
	player._finish_action()
	assert(player.action_state == "" and not player.air_attack.active)
	await _reset()
	player.targeting.using_gamepad = true
	player._start_attack(0, true)
	player.hit_emitted = true
	player.sprite.elapsed = float(player.sprite.clips.jump_attack.length)
	player.throw_buffer_until = player.clock + 1
	player._finish_action()
	assert(player.action_state == "throw" and not player.air_attack.active)
	player._clear_projectile()
	await _reset()
	_body(
		StaticBody2D.new(),
		Vector2(0, player.body_size.y * 0.5 + 50),
		Vector2(400, 100),
		Collision.SOLID
	)
	await _flush()
	player.position.y -= player.safe_margin
	player.velocity = Vector2(0, 120)
	player.move_source_velocity()
	assert(player.is_on_floor())
	player._start_attack(0, true)
	player.hit_emitted = true
	player.sprite.elapsed = float(player.sprite.clips.jump_attack.length)
	player._finish_action()
	assert(player.action_state == "", "Grounded finish must not wait for another update")


func _handoffs() -> void:
	for next in ["jump", "dash", "attack", "throw", "damage", "teleport", "die", "respawn"]:
		await _reset()
		player.targeting.using_gamepad = true
		player._start_attack(0, true)
		var before := player.position
		match next:
			"jump":
				player._jump(0)
				assert(
					(
						absf(
							(
								player.velocity.y
								+ player.jump_speed * float(player.physics.airJumpScale)
							)
						)
						< 0.001
					),
					"Air jump velocity was overwritten by attack exit"
				)
			"dash":
				player._start_dash(1)
				assert(absf(player.path_start.x - before.x + 1.6) < 0.001)
			"attack":
				player._start_attack(0)
				assert(absf(player.path_start.x - before.x + 1.6) < 0.001)
			"throw":
				player.throw_projectile(Vector2.RIGHT)
				assert(player.projectile.global_position == player.body_shape.global_position)
			"damage":
				var knockback: Dictionary = (
					player
					. tuning
					. attacks
					. AttackInfo
					. AttackInfos[0]
					. AttackKnockBackInfo
					. duplicate(true)
				)
				knockback.DirectionX = 1
				assert(player.receive_damage(0, knockback))
				assert(absf(player.path_start.x - before.x + 1.6) < 0.001)
			"die":
				player.die(true)
				assert(player.dead and player.velocity == Vector2.ZERO)
			"teleport":
				player.projectile_active = true
				player.projectile_stuck = true
				player.projectile_normal = Vector2.LEFT
				player.projectile.global_position = before + Vector2(400, 0)
				# This fixture has no wall: native search preserves the free center.
				var expected: Vector2 = (
					player.projectile.global_position - player.body_shape.position
				)
				var origins: Array[Vector2] = []
				var capture := func(from: Vector2, _to: Vector2): origins.append(from)
				player.teleported.connect(capture)
				assert(player.try_teleport())
				player.teleported.disconnect(capture)
				assert(player.position.distance_to(expected) < 0.001)
				assert(origins.size() == 1 and absf(origins[0].x - before.x + 1.6) < 0.001)
			"respawn":
				player.checkpoint = before + Vector2(500, 0)
				player.respawn()
				assert(player.position == player.checkpoint)
		assert(not player.air_attack.active)
		if next not in ["respawn", "teleport"]:
			assert(
				absf(player.position.x - before.x + 1.6) < 0.001,
				"Exit offset ordering failed: " + next
			)
		player._clear_projectile()


func _weak_handoff() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy in lab.stage.enemies:
		enemy.set_physics_process(false)
	await _flush()
	var target: Node = lab.stage.enemies[0]
	target.kunai.weak_points = 2
	lab.player.targeting.using_gamepad = true
	lab.player._start_attack(0, true)
	assert(lab.player.weak_dash.start(target))
	assert(not lab.player.air_attack.active and lab.player.action_state == "weakpoint_execution")
	assert(lab.player.weak_dash.motion_start == lab.player.body_shape.global_position)
	lab.queue_free()
	await _flush()
