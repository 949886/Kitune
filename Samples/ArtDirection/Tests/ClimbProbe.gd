extends SceneTree
## Native climb visuals are chosen from motion/contact, not requested input.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const STEP := 1.0 / 60.0
var player: CharacterBody2D
var terrain := Node2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(terrain)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	for side in [-1.0, 1.0]:
		await _reset()
		_wall(side, -100, 200)
		await _flush()
		player.facing = side
		player.climbing = true
		player._move_normally(STEP, 0, 0)
		player._update_locomotion_animation(0, 0)
		assert(player.climb.bottom_contact and player.sprite.clip_name == "climb")
		player._move_normally(STEP, 0, -1)
		player._update_locomotion_animation(0, -1)
		assert(player.sprite.clip_name == "climb_up")
		# Holding up cannot select ClimbUp after the source hold clock runs out.
		player.wall_hold_time = -1
		player.velocity.y = 100
		player._move_normally(STEP, 0, -1)
		player._update_locomotion_animation(0, -1)
		assert(player.velocity.y > 0 and player.sprite.clip_name == "climb_down")
		await _reset()
		_wall(side, -100, 80)
		await _flush()
		player.facing = side
		player.climbing = true
		player._move_normally(STEP, 0, 0)
		player._update_locomotion_animation(0, 0)
		assert(player.climb.side_contact and not player.climb.bottom_contact)
		assert(player.sprite.clip_name == "climb_corner")
		assert(player.sprite.texture != null)
	# A roof stops actual ascent even while the player keeps pressing up.
	await _reset()
	_wall(1, -100, 200)
	_box(Rect2(-50, -60, 100, 14.96))
	await _flush()
	player.climbing = true
	player._move_normally(STEP, 0, -1)
	player._update_locomotion_animation(0, -1)
	assert(player.is_on_ceiling() and player.sprite.clip_name == "climb")
	# The clock advances through ordinary airborne updates and scaled time;
	# throwing skips it, and changing the wall does not refill it.
	await _reset()
	player.wall_hold_time = 1.0
	player.source_time_scale = 0.5
	player._physics_process(STEP)
	assert(absf(player.wall_hold_time - (1.0 - STEP * 0.5)) < 0.00001)
	var remaining: float = player.wall_hold_time
	player.action_state = "throw"
	player._physics_process(STEP)
	assert(player.wall_hold_time == remaining)
	player.action_state = ""
	player.source_time_scale = 0
	player._physics_process(STEP)
	assert(player.wall_hold_time == remaining)
	# Native LateUpdate skips movement during a ceiling hold even after expiry.
	await _reset()
	player.ceiling_hang = true
	player.wall_hold_time = STEP * 0.5
	var position_before: Vector2 = player.position
	for index in 120:
		player._physics_process(STEP)
	assert(player.wall_hold_time < 0 and player.ceiling_hang)
	assert(player.position == position_before and player.sprite.clip_name == "climb_ceiling")
	player._jump(0)
	assert(not player.ceiling_hang)
	player._physics_process(STEP)
	assert(player.position.y > position_before.y)
	# The shipped million-second float does not decrease by one 60 Hz step.
	player.wall_hold_time = float(player.physics.WallHoldingTime)
	player.climb.advance(STEP)
	assert(player.wall_hold_time == float(player.physics.WallHoldingTime))
	player.wall_hold_time = -1
	player._start_dash(1)
	assert(player.wall_hold_time == float(player.physics.WallHoldingTime))
	# Respawn restores the same source duration.
	player.wall_hold_time = -1
	player.respawn()
	assert(player.wall_hold_time == float(player.physics.WallHoldingTime))
	# Start on a real floor, then use the real kunai flight and teleport entry.
	# A cached pre-teleport floor flag must not cancel the new ceiling hold.
	await _reset()
	_box(Rect2(-100, 0, 200, 20))
	_box(Rect2(-100, -120, 200, 20))
	await _flush()
	for index in 3:
		player._physics_process(STEP)
	assert(player.is_on_floor())
	player.throw_projectile(Vector2.UP)
	for index in 6:
		player._physics_process(STEP)
	assert(player.projectile_stuck and player.projectile_normal.y > 0)
	assert(player.try_teleport() and player.ceiling_hang)
	var ceiling_position: Vector2 = player.position
	for index in 120:
		player._physics_process(STEP)
	assert(player.ceiling_hang and player.position.is_equal_approx(ceiling_position))
	assert(player.sprite.clip_name == "climb_ceiling")
	print("CLIMB_PASS")
	quit()


func _reset() -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.respawn()
	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.action_state = ""
	player.facing = 1
	player.source_time_scale = 1
	player.wall_hold_time = float(player.physics.WallHoldingTime)
	player.climb.side_contact = false
	player.climb.bottom_contact = false
	player._clear_move_contacts()
	# Refresh Godot's cached floor/ceiling state in the now empty fixture.
	player.move_and_slide()
	await _flush()


func _wall(side: float, top: float, height: float) -> void:
	var edge: float = side * (player.body_size.x * 0.5 + player.ground_snap.skin)
	_box(Rect2(edge if side > 0 else edge - 20, top, 20, height))


func _box(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Collision.SOLID | Collision.PROJECTILE_SURFACE
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
