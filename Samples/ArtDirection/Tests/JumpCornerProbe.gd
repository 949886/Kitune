extends SceneTree
## Actual roof collisions: native side correction, retained ascent and exclusions.

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
	assert(player.jump_corner.settings.vertical_ray_count == 3)
	assert(is_equal_approx(player.jump_corner.spacing, 6.4))
	for side in [-1, 1]:
		await _reset()
		_box(Rect2(-60 if side < 0 else 0, -60, 60, 10))
		await _flush()
		player.velocity = Vector2(0, -600)
		player.move_source_velocity()
		assert(player.jump_corner.adjusted)
		assert(is_equal_approx(player.position.x, -side * 19.2))
		assert(absf(player.position.y + 14.96) < 0.002)
		assert(player.velocity.y == -600 and not player.source_touched_ceiling)
		# A second free step continues the ascent instead of immediately stopping.
		var previous: Vector2 = player.position
		player.move_source_velocity()
		assert(absf(player.position.y - previous.y + 10.0) < 0.002)
		assert(is_equal_approx(player.position.x, previous.x))
	# A middle-only obstruction follows the source's leftward fallback.
	await _reset()
	_box(Rect2(-1, -60, 2, 10))
	await _flush()
	player.velocity = Vector2(0, -600)
	player.move_source_velocity()
	assert(player.jump_corner.adjusted and is_equal_approx(player.position.x, -19.2))
	# Horizontal travel occurs before the correction; Teleport clears returned X.
	await _reset()
	_box(Rect2(-60, -60, 60, 10))
	await _flush()
	player.velocity = Vector2(120, -600)
	player.move_source_velocity()
	assert(player.jump_corner.adjusted and is_equal_approx(player.position.x, 21.2))
	assert(player.velocity == Vector2(0, -600))
	# The original callback uses the player's velocity, not an explicit offset.
	for retained_y in [-300.0, 300.0]:
		await _reset()
		_box(Rect2(-60, -60, 60, 10))
		await _flush()
		player.velocity = Vector2(120, retained_y)
		player.move_source_offset(Vector2(0, -10))
		assert(player.jump_corner.adjusted == (retained_y < 0))
		assert(player.velocity == Vector2(120, retained_y))
		if retained_y < 0:
			assert(absf(player.position.y + 9.96) < 0.002)
	await _reset()
	_box(Rect2(-60, -60, 60, 10))
	await _flush()
	player.source_time_scale = 0.5
	player.velocity = Vector2(0, -600)
	player.move_source_velocity()
	assert(player.jump_corner.adjusted and is_equal_approx(player.position.x, 19.2))
	assert(absf(player.position.y + 9.96) < 0.002 and player.velocity.y == -600)
	# A nearby wall overlaps the first correction target. Search must find a
	# free body position before continuing upward, without leaving it in terrain.
	await _reset()
	_box(Rect2(-60, -60, 60, 10))
	_box(Rect2(24, -100, 20, 200))
	await _flush()
	player.velocity = Vector2(0, -600)
	player.move_source_velocity()
	assert(player.jump_corner.adjusted and player.position.x < 19.2)
	assert(player.position.x > 6.4 and player.position.y < -10)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.body_shape.shape
	query.transform = player.body_shape.global_transform
	query.collision_mask = Collision.SOLID
	query.exclude = [player.get_rid()]
	assert(player.get_world_2d().direct_space_state.intersect_shape(query).is_empty())
	await _reset()
	_box(Rect2(-60, -60, 120, 10))
	await _flush()
	player.velocity = Vector2(0, -600)
	player.move_source_velocity()
	assert(not player.jump_corner.adjusted and player.position.x == 0)
	assert(player.velocity.y == 0 and player.source_touched_ceiling)
	for state in ["throw", "climbing"]:
		await _reset()
		_box(Rect2(-60, -60, 60, 10))
		await _flush()
		player.action_state = state if state == "throw" else ""
		player.climbing = state == "climbing"
		player.velocity = Vector2(0, -600)
		player.move_source_velocity()
		assert(not player.jump_corner.adjusted and player.position.x == 0)
	# The source upward mask ignores one-way platforms entirely.
	await _reset()
	_box(Rect2(-60, -60, 60, 10), Collision.ONE_WAY)
	await _flush()
	player.velocity = Vector2(0, -600)
	player.move_source_velocity()
	assert(not player.jump_corner.adjusted and player.position.x == 0)
	print("JUMP_CORNER_PASS")
	quit()


func _reset() -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.respawn()
	player.position = Vector2.ZERO
	player.action_state = ""
	player.climbing = false
	player.velocity = Vector2.ZERO
	player.source_time_scale = 1.0
	await _flush()


func _box(rect: Rect2, layer := Collision.SOLID) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	collider.position = rect.get_center()
	collider.one_way_collision = layer == Collision.ONE_WAY
	body.add_child(collider)
	terrain.add_child(body)


func _flush() -> void:
	await physics_frame
	await process_frame
