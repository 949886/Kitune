extends SceneTree
## Analytic obstacle fixtures for native search order, attachment and exhaustion.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
var player: CharacterBody2D
var terrain := Node2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(terrain)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	await _reset()
	_box(Rect2(-5, -5, 10, 10))
	await _flush()
	var previous: Vector2 = player.position
	var result: Dictionary = player.teleport.find_position(Vector2.ZERO, Collision.SOLID)
	# At radius 6 all directions overlap. At radius 12 the fourth direction
	# (leftward displacement) is the first free full-body position.
	assert(result.shifted and result.wall_direction == Vector2.RIGHT)
	assert(result.center.is_equal_approx(Vector2(-12, -0.24)))
	assert(player.position == previous, "Searching must not move the live body")
	result = player.teleport.find_position(Vector2(100, 100), Collision.SOLID)
	assert(not result.shifted and result.center == Vector2(100, 100))
	await _reset()
	_box(Rect2(-5, -5, 10, 10), Collision.ONE_WAY)
	await _flush()
	result = player.teleport.find_position(Vector2.ZERO, Collision.SOLID)
	assert(not result.shifted and result.center == Vector2.ZERO)
	result = player.teleport.find_position(Vector2.ZERO, Collision.SOLID | Collision.ONE_WAY)
	assert(result.shifted and result.center.is_equal_approx(Vector2(-12, -0.24)))
	var diagonal_drop := 12.0 / sqrt(2.0) - 0.24
	for layer_name in ["Wall", "HardWall"]:
		await _reset()
		_box(Rect2(0, -100, 20, 200), Collision.SOLID, layer_name)
		await _flush()
		player.teleport.apply(Vector2.ZERO, false)
		assert(player.body_shape.global_position.is_equal_approx(Vector2(-6.64, diagonal_drop)))
		assert(player.climbing == (layer_name == "Wall") and not player.ceiling_hang)
	# A wall below head height is caught by the fifth top-to-bottom ray.
	await _reset()
	_box(Rect2(0, 0, 20, 100))
	await _flush()
	player.teleport.apply(Vector2.ZERO, false)
	assert(player.climbing)
	assert(
		(
			player.body_shape.global_position.distance_to(Vector2(-6.64, diagonal_drop + 4 * 4.48))
			< 0.01
		)
	)
	await _reset()
	_box(Rect2(-100, 0, 200, 20))
	await _flush()
	player.teleport.apply(Vector2.ZERO, false)
	assert(player.body_shape.global_position.distance_to(Vector2(0, -22.64)) < 0.01)
	assert(not player.climbing and not player.ceiling_hang)
	await _reset()
	_box(Rect2(-100, -120, 200, 20))
	await _flush()
	player.teleport.apply(Vector2(0, -100), false)
	assert(player.ceiling_hang)
	assert(player.body_shape.global_position.distance_to(Vector2(0, -93.36)) < 0.01)
	# An obstacle can overlap a previously stuck blade. The actual player
	# entry must search and spend stamina instead of rejecting that target.
	await _reset()
	_box(Rect2(-5, -5, 10, 10))
	await _flush()
	player.projectile_active = true
	player.projectile_stuck = true
	player.projectile.global_position = Vector2.ZERO
	var stamina_before: float = player.stamina
	assert(player.try_teleport())
	assert(player.climbing and not player.projectile_active)
	assert(is_equal_approx(stamina_before - player.stamina, 8.0))
	assert(player.body_shape.global_position.distance_to(Vector2(-11.64, 17.68)) < 0.01)
	# The shipped fallback keeps the requested point after all 200 rings fail.
	await _reset()
	_box(Rect2(-3000, -3000, 6000, 6000))
	await _flush()
	result = player.teleport.find_position(Vector2.ZERO, Collision.SOLID)
	assert(not result.shifted and result.wall_direction == Vector2.ZERO)
	assert(result.center == Vector2.ZERO)
	print("TELEPORT_PASS")
	quit()


func _reset() -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.checkpoint = Vector2(-100, 0)
	player.respawn()
	player.action_state = ""
	player.velocity = Vector2.ZERO
	player.source_time_scale = 1
	player._clear_move_contacts()
	player.move_and_slide()
	await _flush()


func _box(rect: Rect2, mask := Collision.SOLID, source_layer := "Wall") -> void:
	var body := StaticBody2D.new()
	body.collision_layer = mask
	if mask & Collision.SOLID:
		body.collision_layer |= Collision.STATIC_SURFACE
		if source_layer in ["Wall", "Ground"]:
			body.collision_layer |= Collision.STUCK_SURFACE
	body.set_meta("source_layer", source_layer)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	collider.position = rect.get_center()
	body.add_child(collider)
	terrain.add_child(body)


func _flush() -> void:
	await physics_frame
	await process_frame
