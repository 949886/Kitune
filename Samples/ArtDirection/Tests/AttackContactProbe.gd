extends SceneTree
## Native body overlap gate: suppress new motion, preserve animation and damage.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")


class Receiver:
	extends StaticBody2D
	var hits: Array[Dictionary] = []

	func receive_study_hit(payload: Dictionary, _direction: float) -> bool:
		hits.append(payload)
		return true


var player: CharacterBody2D
var fixtures := Node2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(fixtures)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(123, 456)
	var contract: Dictionary = player.gravity_motion.settings.attack_contact
	assert(contract.patterns == ["PlayerAttackPattern", "PlayerStrongAttackPattern"])
	assert(contract.size_profile_field == "ClosestEnemyCeckBoxSize")
	assert(contract.layer == "Enemy" and contract.angle == 0)
	assert(player.combat[contract.size_profile_field] == {"x": 0.0, "y": 0.0})
	await _queries()
	await _attacks()
	await _source_enemies()
	player.queue_free()
	fixtures.queue_free()
	await process_frame
	print("ATTACK_CONTACT_PASS")
	quit()


func _flush() -> void:
	await physics_frame
	await process_frame


func _clear() -> void:
	for child in fixtures.get_children():
		child.queue_free()
	await _flush()


func _box(offset: Vector2, layer: int, area := false) -> CollisionObject2D:
	var body: CollisionObject2D = Area2D.new() if area else Receiver.new()
	body.collision_layer = layer
	body.position = player.body_shape.global_position + offset
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 8)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	fixtures.add_child(body)
	return body


func _queries() -> void:
	await _clear()
	assert(not player.gravity_motion.attack_enemy_contact())
	for layer in [Collision.ENEMY_TARGET, Collision.DAMAGEABLE, Collision.SOLID, Collision.ONE_WAY]:
		for area in [false, true]:
			await _clear()
			_box(Vector2.ZERO, layer, area)
			await _flush()
			assert(
				player.gravity_motion.attack_enemy_contact() == (layer == Collision.ENEMY_TARGET)
			)
	# Compare geometric bounds, with a gap on either side of the edge to avoid
	# assuming Unity and Godot agree on exact-touch floating-point conventions.
	for side in [-1.0, 1.0]:
		for gap in [-0.1, 0.1]:
			for axis in [Vector2.RIGHT, Vector2.DOWN]:
				await _clear()
				var half_extent: float = player.body_size.dot(axis) * 0.5 + 4.0
				_box(axis * (half_extent + gap) * side, Collision.ENEMY_TARGET)
				await _flush()
				player.facing = -side
				assert(player.gravity_motion.attack_enemy_contact() == (gap < 0.0))
	# The profile stores an additive full box size in Unity units, not a radius.
	var field: String = player.gravity_motion.settings.attack_contact.size_profile_field
	var original: Dictionary = player.combat[field]
	for offset in [Vector2(15, 0), Vector2(0, 35)]:
		await _clear()
		_box(offset, Collision.ENEMY_TARGET)
		await _flush()
		assert(not player.gravity_motion.attack_enemy_contact())
		player.combat[field] = {"x": 1.0, "y": 2.0}
		assert(player.gravity_motion.attack_enemy_contact())
		player.combat[field] = original


func _attacks() -> void:
	for index in 4:
		await _clear()
		var enemy := _box(Vector2(5, 0), Collision.ENEMY_TARGET | Collision.DAMAGEABLE) as Receiver
		await _flush()
		player.facing = 1.0
		player.path_duration = 0.0
		player.path_time = 0.0
		player.velocity = Vector2(42, 12)
		player.curve_time = 0.37
		var start := player.position
		player._start_attack(index if index < 3 else 0, false, index == 3)
		assert(player.path_duration == 0.0 and player.path_time == 0.0)
		assert(player.velocity == Vector2(42, 12) and player.curve_time == 0.37)
		assert(player.position == start and not player.attack_info.is_empty())
		assert(
			player.sprite.clip_name == ("attack%d" % (index + 1) if index < 3 else "heavy_attack")
		)
		# Drive the real hit check at its imported animation frame. Suppressing
		# movement must neither cancel nor double-deliver the original attack.
		player.sprite.elapsed = (
			float(player.attack_info.AttackCheckInfo.AttackCheckStartFrame) / 60.0 + 0.001
		)
		player._finish_action()
		player._finish_action()
		assert(enemy.hits.size() == 1 and player.hit_emitted)
		assert(enemy.hits[0].interaction == (4 if index < 3 else 8))
		assert(enemy.hits[0].Damage == player.attack_info.Damage)
		if index == 3:
			assert(player.heavy_ready_at > player.clock)
			assert(player.audio.last_selection.has("heavy_attack"))
		# The gate is checked again for each combo entry, rather than cached for
		# the whole chain. Removing the collider immediately permits new motion.
		enemy.collision_layer = 0
		await _flush()
		player._start_attack(index if index < 3 else 0, false, index == 3)
		assert(player.path_duration > 0.0 and player.path_time == 0.0)
		assert(player.path_collision_type == "Attack" and player.velocity == Vector2.ZERO)
		assert(player.path_target.x > player.path_start.x)

	await _clear()
	_box(Vector2.ZERO, Collision.ENEMY_TARGET)
	await _flush()
	# Original ApplyAttackMovement is a no-op when blocked. It must not erase
	# any movement already running when a state transition enters this pattern.
	player._start_motion(99, 0.5, player.physics.dashPhysicsCurve, "Hit")
	player.path_time = 0.1
	var target: Vector2 = player.path_target
	player._start_attack(0, false, true)
	assert(player.path_target == target and player.path_time == 0.1 and player.path_duration == 0.5)
	assert(player.path_collision_type == "Hit")
	# JumpAttack uses Airing directly and ignores the ground-attack contact gate.
	player._start_attack(0, true)
	assert(player.action_state == "attack_air" and not player.can_air_attack)
	assert(player.path_time == player.path_duration)
	assert(
		player.velocity.y == -float(player.attack_info.AttackMovementInfo.Distance) * player.units
	)
	assert(player.sprite.clip_name == "jump_attack")


func _source_enemies() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy in lab.stage.enemies:
		enemy.set_physics_process(false)
	await _flush()
	var kinds: Dictionary = {}
	for enemy in lab.stage.enemies:
		lab.player.global_position = (
			enemy.body_shape.global_position - lab.player.body_shape.position
		)
		lab.player.force_update_transform()
		assert(lab.player.gravity_motion.attack_enemy_contact())
		kinds[enemy.data.kind] = true
	assert(kinds.size() == 3)
	lab.queue_free()
	await _flush()
	print("ATTACK_CONTACT_SOURCE_ENEMIES kinds=", kinds.keys())
