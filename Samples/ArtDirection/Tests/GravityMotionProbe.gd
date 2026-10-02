extends SceneTree
## Independent closed-form combo oracle and real body tests for the native driver.

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
	var data: Dictionary = player.gravity_motion.settings
	assert(data.collision_types == ["Attack", "Hit"])
	assert(data.extra_input_multiplier == 0.8 and data.active_input_threshold == 0.1)
	assert(data.default_layers == data.static_layers + ["InteractiveWall"])
	for value: String in data.source_sha256.values():
		assert(value.length() == 64)
	await _combos()
	await _heavy()
	await _hit_input()
	await _clamped_curve()
	await _landing()
	await _guard()
	await _time_scale()
	player.queue_free()
	terrain.queue_free()
	await process_frame
	print("GRAVITY_MOTION_PASS")
	quit()


func _flush() -> void:
	await physics_frame
	await process_frame


func _reset(grounded := false) -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.position = Vector2(0, -10000)
	player.source_time_scale = 1.0
	player.velocity = Vector2.DOWN
	player.move_source_velocity()  # Clear CharacterBody2D's previous contact cache.
	player.position = Vector2(0, -player.safe_margin if grounded else 0.0)
	player.facing = 1.0
	player.action_state = ""
	player.path_time = player.path_duration
	player.jump_held = false
	if grounded:
		_box(Rect2(-2000, 0, 4000, 100))
		await _flush()
		player.velocity = Vector2.DOWN * 120.0
		player.move_source_velocity()
		assert(player.is_on_floor())
	player.gravity_motion.refresh_ray_origins()


func _box(rect: Rect2, mask := Collision.SOLID | Collision.STATIC_SURFACE, area := false) -> void:
	var body: CollisionObject2D = Area2D.new() if area else StaticBody2D.new()
	body.collision_layer = mask
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.position = rect.get_center()
	body.add_child(collider)
	terrain.add_child(body)


func _combos() -> void:
	for index in 3:
		await _reset(true)
		player._start_attack(index)
		var distance: float = player.path_target.x - player.path_start.x
		var duration: float = player.path_duration
		var expected := 0.0
		var elapsed := 0.0
		var frames := 0
		while player.path_time < player.path_duration and frames < 30:
			await _flush()
			elapsed = float(PackedFloat32Array([elapsed + float(PackedFloat32Array([STEP])[0])])[0])
			# Native two-key Hermite is 2t-t^2, so speed is D/T * (1-t)^2.
			if elapsed < duration:
				expected += distance / duration * pow(1.0 - elapsed / duration, 2) * STEP
			player._follow_motion_curve(STEP, -1.0 if frames < 11 else 0.0)
			frames += 1
			assert(
				absf(player.position.x - expected) < 0.003,
				(
					"combo %s frame %s actual=%s expected=%s elapsed=%s kind=%s floor=%s"
					% [
						index,
						frames,
						player.position.x,
						expected,
						elapsed,
						player.path_collision_type,
						player.is_on_floor()
					]
				)
			)
		assert(frames == 12, "C# float duration must end the 0.2 s attack on frame 12")
		assert(player.path_collision_type == "Idle" and player.curve_time == 0.0)
		assert(player.velocity.y == 0.0 and player.is_on_floor())
		assert(
			player.floor_stop_on_slope, "Gravity movement must restore the ordinary solver option"
		)
		print("GRAVITY_COMBO index=", index, " distance=", player.position.x)


func _heavy() -> void:
	await _reset(true)
	player._start_attack(0, false, true)
	for frame in 24:
		await _flush()
		player._follow_motion_curve(STEP, 0.0)
	assert(player.position.x < 1.0, "Charge must not teleport to the 90-unit target")
	var charge_x := player.position.x
	while player.path_time < player.path_duration:
		await _flush()
		player._follow_motion_curve(STEP, 0.0)
	assert(player.position.x > 35.0 and player.position.x < 130.0)
	assert(player.action_state == "heavy_attack", "Movement ending must preserve animation")
	print("GRAVITY_HEAVY charge=", charge_x, " final=", player.position.x)


func _constant(value: float) -> Dictionary:
	return {"m_Curve": [{"time": 0.0, "value": value, "inSlope": 0.0, "outSlope": 0.0}]}


func _hit_input() -> void:
	for horizontal: float in [-1.0, -0.1, 0.0, 0.1, 1.0]:
		await _reset()
		player._start_motion(-60.0, 0.25, _constant(0), "Hit")
		await _flush()
		player._follow_motion_curve(STEP, horizontal)
		var expected := -240.0 + (horizontal * 268.8 if absf(horizontal) > 0.1 else 0.0)
		assert(absf(player.velocity.x - expected) < 0.001)
		assert(absf(player.position.x - expected * STEP) < 0.001)
		assert(absf(player.velocity.y - player.gravity * STEP) < 0.001)
		# Terminal ResetDashMovement applies even tiny input, keeps curveTime,
		# ignores old target X and retains its previous intended velocity X.
		var previous := player.position
		player.path_time = player.path_duration - STEP * 0.5
		player.curve_time = 0.37
		var old_velocity := player.velocity
		await _flush()
		player._follow_motion_curve(STEP, horizontal)
		assert(absf(player.position.x - previous.x - horizontal * 268.8 * STEP) < 0.001)
		assert(player.velocity.x == old_velocity.x and player.curve_time == 0.37)
		assert(absf(player.velocity.y - old_velocity.y - player.gravity * STEP) < 0.001)
		assert(player.path_collision_type == "Idle")


func _clamped_curve() -> void:
	for value in [-2.0, 2.0]:
		await _reset()
		player._start_motion(60.0, 0.25, _constant(value), "Attack")
		player.jump_held = true  # Gravity branch ignores jump-hold scaling.
		player.path_target.y = -30.0
		await _flush()
		player._follow_motion_curve(STEP, 1.0)
		assert(absf(player.velocity.x - (240.0 if value < 0 else 0.0)) < 0.001)
		assert(absf(player.velocity.y - (-120.0 + player.gravity * STEP)) < 0.001)


func _landing() -> void:
	await _reset()
	_box(Rect2(-200, 3, 400, 100))
	await _flush()
	player._start_motion(0.0, 1.0, _constant(1), "Attack")
	player.action_state = "attack"
	var frames := 0
	while player.path_time < player.path_duration and frames < 20:
		await _flush()
		player._follow_motion_curve(STEP, 0.0)
		frames += 1
	assert(frames < 20 and player.is_on_floor())
	assert(player.path_collision_type == "Idle" and player.action_state == "attack")
	assert(player.velocity.y > 0.0, "Native active driver assigns intended velocity after OnLand")


func _guard() -> void:
	for side in [-1.0, 1.0]:
		for depth in [0.95, 0.97]:
			await _reset()
			_box(Rect2(-100, depth, 200, 30), Collision.STATIC_SURFACE, true)
			await _flush()
			assert(player.gravity_motion.wall_or_edge(Vector2(side * 2, 0)) == (depth > 0.96))
	await _reset()
	# A ground query on InteractiveWall works; the horizontal wall query ignores it.
	_box(Rect2(-100, 0.5, 200, 30), Collision.INTERACTIVE_WALL, true)
	await _flush()
	assert(not player.gravity_motion.wall_or_edge(Vector2(2, 0)))
	assert(player.gravity_motion.wall_or_edge(Vector2(200, 0)))
	# Downward lookahead uses full length and cached feet; wall origins refresh.
	await _reset()
	_box(Rect2(11, 0.5, 2, 10), Collision.STATIC_SURFACE, true)
	await _flush()
	assert(not player.gravity_motion.wall_or_edge(Vector2(0, 5)))
	player.position.x = 100
	assert(not player.gravity_motion.wall_or_edge(Vector2(0, 5)))
	assert(player.gravity_motion.wall_or_edge(Vector2(0, 5)))
	# Walls block heavy X but preserve the source intended velocity for the next step.
	await _reset(true)
	_box(Rect2(7, -80, 20, 90))
	await _flush()
	player._start_motion(60.0, 0.25, _constant(0), "Attack")
	player.action_state = "heavy_attack"
	player._follow_motion_curve(STEP, 0.0)
	assert(absf(player.position.x) < 0.001 and player.velocity.x == 240.0)
	player.action_state = ""
	player._start_motion(60.0, 0.25, _constant(0), "Hit")
	await _flush()
	player._follow_motion_curve(STEP, 0.0)
	assert(player.position.x < 1.0 and player.velocity.x == 240.0)
	# A cliff is checked only for StrongAttack; ordinary ground attacks can leave it.
	await _reset()
	player._start_motion(60.0, 0.25, _constant(0), "Attack")
	player.action_state = "heavy_attack"
	await _flush()
	player._follow_motion_curve(STEP, 0.0)
	assert(player.position.x == 0.0 and player.velocity.x == 240.0)
	player.action_state = "attack"
	await _flush()
	player._follow_motion_curve(STEP, 0.0)
	assert(player.position.x > 3.9)


func _time_scale() -> void:
	await _reset()
	player._start_motion(60.0, 0.25, _constant(0), "Hit")
	player.source_time_scale = 0.25
	await _flush()
	player._follow_motion_curve(STEP * 0.25, 0.0)
	assert(absf(player.position.x - 1.0) < 0.001)
	assert(absf(player.velocity.y - player.gravity * STEP * 0.25) < 0.001)
	var previous := player.position
	var elapsed: float = player.path_time
	player.source_time_scale = 0.0
	await _flush()
	player._follow_motion_curve(0.0, 1.0)
	assert(player.position == previous and player.path_time == elapsed)
