extends SceneTree
## Native two-foot queries, layer filtering and actual curve-movement integration.

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
	var source: Dictionary = player.ground_snap.settings
	assert(source.horizontal_ray_count == 11)
	assert(is_equal_approx(player.ground_snap.maximum_distance, 22.4))
	assert(is_equal_approx(player.safe_margin, 0.24))
	assert(source.static_layers == ["Ground", "Wall", "HardWall", "Platform"])
	assert(source.excluded_state_flag == "DashAttack")
	for hash_value: String in source.source_sha256.values():
		assert(hash_value.length() == 64)
	await _reset()
	_expect_snap(INF)

	await _reset()
	_box(Rect2(-100, 12, 200, 20))
	await _flush()
	_expect_snap(12)

	await _reset()
	_box(Rect2(-30, 14, 30, 20))
	_box(Rect2(0, 8, 30, 20))
	await _flush()
	_expect_snap(8)  # Unity picks the higher hit, not the average or the center.

	await _reset()
	_box(Rect2(-30, 9, 30, 20))
	await _flush()
	_expect_snap(9)  # One supported foot is sufficient at an edge.

	await _reset()
	_box(Rect2(-1, 8, 2, 20))
	await _flush()
	_expect_snap(INF)  # A center-only support is intentionally missed by the source.

	for distance in [22.39, 22.41]:
		await _reset()
		_box(Rect2(-100, distance, 200, 20))
		await _flush()
		_expect_snap(distance if distance < 22.4 else INF)

	await _reset()
	var slope := StaticBody2D.new()
	slope.collision_layer = Collision.SOLID | Collision.STATIC_SURFACE
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array(
		[Vector2(-20, 18), Vector2(20, 8), Vector2(20, 40), Vector2(-20, 40)]
	)
	slope.add_child(shape)
	terrain.add_child(slope)
	await _flush()
	_expect_snap(13.0 - float(player.body_size.x) * 0.5 * 0.25)

	# GetGroundPoint uses Static, independent of the player's temporary drop mask.
	await _reset()
	player.drop_time = 0.2
	player.set_collision_mask_value(3, false)
	_box(Rect2(-100, 10, 200, 20), Collision.ONE_WAY | Collision.STATIC_SURFACE)
	await _flush()
	_expect_snap(10)
	for mask in [Collision.SOLID, Collision.SOLID | Collision.INTERACTIVE_WALL]:
		await _reset()
		_box(Rect2(-100, 10, 200, 20), mask)
		await _flush()
		_expect_snap(INF)

	await _reset()
	_box(Rect2(-100, 7, 200, 20), Collision.STATIC_SURFACE, true)
	await _flush()
	_expect_snap(7)
	await _reset()
	_box(Rect2(-100, -1, 200, 20))
	await _flush()
	_expect_snap(0)  # queriesStartInColliders produces a hit at the ray origin.

	await _verify_curve()
	await _verify_gravity_driver_exemption()
	await _verify_weak_dash_exemption()
	player.queue_free()
	terrain.queue_free()
	await process_frame
	print("GROUND_SNAP_PASS")
	quit()


func _flush() -> void:
	await physics_frame
	await process_frame


func _reset() -> void:
	player.set_physics_process(false)
	for child: Node in terrain.get_children():
		child.queue_free()
	await _flush()
	player.respawn()
	player.set_physics_process(false)
	player.position = Vector2.ZERO
	player.path_start = Vector2.ZERO
	player.path_target = Vector2(100, 0)
	player.path_collision_type = "Dash"
	player.velocity = Vector2(42, 12)
	player.source_time_scale = 1.0
	player.force_update_transform()


func _box(rect: Rect2, mask := Collision.SOLID | Collision.STATIC_SURFACE, area := false) -> void:
	var body: CollisionObject2D = Area2D.new() if area else StaticBody2D.new()
	body.collision_layer = mask
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	body.position = rect.get_center()
	body.add_child(collider)
	terrain.add_child(body)


func _expect_snap(floor_y: float) -> void:
	var before := player.position
	var start: Vector2 = player.path_start
	var target: Vector2 = player.path_target
	var velocity := player.velocity
	var expected := Vector2.ZERO if is_inf(floor_y) else Vector2(0, floor_y - before.y - 0.24)
	var actual: Vector2 = player.ground_snap.apply_to_curve()
	assert(actual.distance_to(expected) < 0.001)
	assert(player.position.distance_to(before + expected) < 0.001)
	assert(player.path_start.distance_to(start + expected) < 0.001)
	assert(player.path_target.distance_to(target + expected) < 0.001)
	assert(player.velocity == velocity, "StickToGround must not rewrite the source velocity")


func _verify_curve() -> void:
	await _reset()
	_box(Rect2(-1000, 0, 1000, 40))
	_box(Rect2(0, 12, 1000, 40))
	await _flush()
	player.position = Vector2(-20, -0.24)
	player.checkpoint = player.position
	player._start_dash(1.0)
	player.set_physics_process(true)
	var descended := false
	for frame in 14:
		await _flush()
		if player.position.x > player.body_size.x * 0.5:
			if descended:
				assert(
					player.is_on_floor(),
					"Curve movement retained stale airborne contact after snapping"
				)
			descended = true
			assert(absf(player.position.y - 11.76) < 0.01, "Dash hovered above the lower step")
			assert(absf(player.path_start.y - 11.76) < 0.01)
			assert(absf(player.path_target.y - 11.76) < 0.01)
	assert(descended)
	print("GROUND_SNAP_CURVE position=", player.position, " grounded=", player.is_on_floor())
	player.set_physics_process(false)
	player.source_time_scale = 0.0
	var frozen := player.position
	player.set_physics_process(true)
	for frame in 3:
		await _flush()
	assert(player.position == frozen)
	player.set_physics_process(false)


func _verify_weak_dash_exemption() -> void:
	await _reset()
	_box(Rect2(-1000, 12, 2000, 40))
	await _flush()
	player.weak_dash.actor = player
	player.weak_dash._begin_motion(
		Vector2(100, -player.body_size.y * 0.5), player.physics.dashPhysicsCurve, 0.3
	)
	player.weak_dash._move(1.0 / 60.0, 0.0)
	assert(
		absf(player.position.y) < 0.001, "DashAttack must not inherit ordinary curve ground snap"
	)


func _verify_gravity_driver_exemption() -> void:
	for kind in ["Attack", "Hit"]:
		await _reset()
		_box(Rect2(-1000, 12, 2000, 40))
		await _flush()
		player._start_motion(100, 0.3, player.physics.dashPhysicsCurve, kind)
		player._follow_motion_curve(1.0 / 60.0, 0.0)
		assert(
			absf(player.position.y - player.gravity / 3600.0) < 0.001,
			"GravityDirectionMove incorrectly inherited ground snap"
		)
