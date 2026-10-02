extends SceneTree
## Native two-move separation: independent numeric cases and collision integration.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const STEP := 1.0 / 60.0


class Enemy:
	extends StaticBody2D
	var run_away := false
	var registered := true

	func player_contact_info() -> Dictionary:
		return {"center": global_position, "run_away": run_away} if registered else {}


class EnemyArea:
	extends Area2D

	func player_contact_info() -> Dictionary:
		return {"center": global_position, "run_away": false}


class Wall:
	extends StaticBody2D
	var hits := 0

	func receive_study_hit(packet: Dictionary, _direction: float) -> void:
		assert(packet.interaction == 2)
		hits += 1


var player: CharacterBody2D
var terrain := Node2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(terrain)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	var source: Dictionary = player.enemy_contact.settings
	assert(source.extra_width == 1.0 and source.minimum_distance == 0.1)
	assert(source.weight_minimum == 1.0 and source.weight_maximum == 5.0)
	assert(source.physics_profile_field == "EnemyDrag" and player.physics.EnemyDrag == 6.0)
	assert(source.excluded_state == "RunAway" and source.layer == "Enemy")
	for hash_value: String in source.source_sha256.values():
		assert(hash_value.length() == 64)
	await _numeric()
	await _query_order()
	await _filters()
	await _collision()
	await _drivers()
	await _source_states()
	player.queue_free()
	terrain.queue_free()
	await process_frame
	print("ENEMY_CONTACT_PASS")
	quit()


func _flush() -> void:
	await physics_frame
	await process_frame


func _reset() -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.source_time_scale = 1.0
	player.position = Vector2(0, -10000)
	player.velocity = Vector2.DOWN
	player.move_source_velocity()
	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.action_state = ""
	player.facing = 1.0


func _body(
	body: CollisionObject2D, center: Vector2, size: Vector2, layer: int
) -> CollisionObject2D:
	body.collision_layer = layer
	body.position = center
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	terrain.add_child(body)
	return body


func _enemy(offset: Vector2, size := Vector2(80, 60)) -> Enemy:
	return (
		_body(Enemy.new(), player.body_shape.global_position + offset, size, Collision.ENEMY_TARGET)
		as Enemy
	)


func _numeric() -> void:
	# Explicit source-unit values cover the denominator floor and both clamp ends.
	var cases := [
		[0.0, 0.0], [0.05, 1.5], [0.1, 3.0], [0.2, 6.0], [0.5, 6.0], [1.0, 6.0], [2.0, 12.0]
	]
	for scale: float in [1.0, 0.25]:
		for side: float in [-1.0, 1.0]:
			for sample in cases:
				await _reset()
				_enemy(Vector2(-side * float(sample[0]) * 16.0, 0))
				await _flush()
				player.source_time_scale = scale
				player.move_source_velocity()
				var drag := side * float(sample[1]) * 16.0
				assert(absf(player.position.x - drag * STEP * scale) < 0.001)
				assert(absf(player.velocity.x - drag / (STEP * scale)) < 0.05)
				assert(player.position.y == 0 and player.velocity.y == 0 and player.facing == 1.0)
	print("ENEMY_CONTACT_NUMERIC cases=", cases.size() * 4)


func _query_order() -> void:
	await _reset()
	_enemy(Vector2(32, 0), Vector2(8, 8))
	await _flush()
	player.velocity = Vector2(960, 0)  # First move enters the contact box at X=16.
	player.move_source_velocity()
	assert(absf(player.position.x - 14.4) < 0.001)
	assert(absf(player.velocity.x + 4800) < 0.01)
	await _reset()
	_enemy(Vector2.ZERO, Vector2(8, 8))
	await _flush()
	player.velocity = Vector2(2400, 0)  # First move exits; no stale-start overlap.
	player.move_source_velocity()
	assert(absf(player.position.x - 40) < 0.001 and player.velocity.x == 2400)
	for offset in [Vector2(18.3, 0), Vector2(18.5, 0), Vector2(0, 26.5)]:
		await _reset()
		_enemy(offset, Vector2(8, 8))
		await _flush()
		player.move_source_velocity()
		assert((absf(player.position.x) > 1.0) == is_equal_approx(offset.x, 18.3))


func _filters() -> void:
	for kind in ["unregistered", "runaway", "wrong_layer", "area", "ordinary_body"]:
		await _reset()
		if kind == "area":
			_body(
				EnemyArea.new(),
				player.body_shape.global_position + Vector2(16, 0),
				Vector2(80, 60),
				Collision.ENEMY_TARGET
			)
		elif kind == "ordinary_body":
			_body(
				StaticBody2D.new(),
				player.body_shape.global_position,
				Vector2(80, 60),
				Collision.ENEMY_TARGET
			)
		else:
			var enemy := _enemy(Vector2(16, 0))
			enemy.registered = kind != "unregistered"
			enemy.run_away = kind == "runaway"
			if kind == "wrong_layer":
				enemy.collision_layer = Collision.DAMAGEABLE
		await _flush()
		player.move_source_velocity()
		assert(absf(player.position.x - (-1.6 if kind == "area" else 0.0)) < 0.001)
	await _reset()
	_enemy(Vector2(16, 0))
	await _flush()
	player.source_time_scale = 0.0
	player.move_source_velocity()
	assert(player.position == Vector2.ZERO and player.velocity == Vector2.ZERO)


func _collision() -> void:
	await _reset()
	_enemy(Vector2(8, 0))
	_body(StaticBody2D.new(), Vector2(-12.4, -30), Vector2(10, 100), Collision.SOLID)
	await _flush()
	player.move_source_velocity()
	assert(player.position.x < 0 and player.position.x > -1.0 and player.is_on_wall())
	assert(
		absf(player.velocity.x + 5760.0) < 0.01,
		"Second base.Move must not replace the returned drag"
	)
	# First move hits a wall, then separation moves away from it. Dash interaction
	# must still reach that wall after Godot replaces the per-move slide list.
	await _reset()
	_enemy(Vector2(26, 0), Vector2(8, 8))
	var wall := _body(Wall.new(), Vector2(25, -30), Vector2(10, 100), Collision.SOLID) as Wall
	await _flush()
	player.action_state = "dash"
	player._start_motion(100, 1.0, {"m_Curve": [{"time": 0.0, "value": 1.0}]})
	player._follow_motion_curve(STEP, 0.0)
	assert(wall.hits == 1 and wall in player.source_slide_bodies)
	assert(player.position.x < 13.0 and player.facing == 1.0)
	# Two base moves must keep flat-floor support, including a horizontal-only push.
	await _reset()
	_body(StaticBody2D.new(), Vector2(0, 50), Vector2(400, 100), Collision.SOLID)
	_enemy(Vector2(16, 0))
	await _flush()
	player.velocity = Vector2(0, 120)
	player.move_source_velocity()
	assert(player.is_on_floor())
	# OnLand can fire in the first move even if separation immediately pushes
	# off that ledge. ResetDashMovement must retain that callback's zero Y.
	await _reset()
	_body(StaticBody2D.new(), Vector2(-52.5, 50), Vector2(95, 100), Collision.SOLID)
	_enemy(Vector2(-16, 0))
	await _flush()
	player.position.y = -player.safe_margin
	player._start_motion(0, 0.25, {"m_Curve": [{"time": 0.0, "value": 1.0}]}, "Hit")
	player.path_time = 0.249
	player.velocity = Vector2(0, 120)
	player._follow_motion_curve(STEP, 0)
	assert(player.source_touched_floor and not player.is_on_floor())
	assert(player.velocity.y == 0.0)
	await _reset()
	_body(StaticBody2D.new(), Vector2(-52.5, 50), Vector2(95, 100), Collision.SOLID)
	_enemy(Vector2(-16, 0))
	await _flush()
	player.position.y = -player.safe_margin
	player._start_motion(0, 1.0, {"m_Curve": [{"time": 0.0, "value": 1.0}]}, "Hit")
	player.path_time = 0.2
	player._follow_motion_curve(STEP, 0)
	assert(player.source_landed and not player.is_on_floor())
	assert(player.path_collision_type == "Idle" and player.velocity.y > 0.0)


func _drivers() -> void:
	await _reset()
	_enemy(Vector2(16, 0))
	await _flush()
	player._start_motion(0, 0.25, {"m_Curve": [{"time": 0.0, "value": 1.0}]}, "Hit")
	player._follow_motion_curve(STEP, 0)
	assert(absf(player.position.x + 1.6) < 0.001)
	assert(player.velocity.x == 0.0, "Gravity driver overwrites Move's return after separation")
	await _reset()
	_enemy(Vector2(16, 0))
	await _flush()
	player.weak_dash.actor = player
	player.weak_dash._begin_motion(
		player.body_shape.global_position, player.physics.dashPhysicsCurve, 0.25
	)
	player.weak_dash._move(STEP, 0)
	assert(absf(player.position.x + 1.6) < 0.001)
	assert(absf(player.velocity.x + 5760) < 0.01)


func _source_states() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy in lab.stage.enemies:
		enemy.set_physics_process(false)
		var old_state: String = enemy.ranged_combat.state
		for state in ["idle", "retreat", "retarget"]:
			enemy.ranged_combat.state = state
			var contact: Dictionary = enemy.player_contact_info()
			assert(contact.center == enemy.body_shape.global_position)
			assert(contact.run_away == (state == "retreat"))
		enemy.ranged_combat.state = old_state
	lab.queue_free()
	await _flush()
