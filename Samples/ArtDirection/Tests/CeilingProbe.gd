extends SceneTree
## Real ceiling kunai attachment: body, sprite pivot, release and respawn geometry.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")
const STEP := 1.0 / 60.0
var player: CharacterBody2D
var terrain := Node2D.new()
var camera := Camera2D.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.add_child(terrain)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	root.add_child(camera)
	camera.zoom = Vector2(6, 6)
	for horizontal in [-60.0, 0.0, 60.0]:
		await _reset()
		_box(Rect2(-200, 0, 400, 20))
		_box(Rect2(-200, -120, 400, 20))
		await _flush()
		for index in 3:
			player._physics_process(STEP)
		assert(player.is_on_floor())
		var target := Vector2(horizontal, -100)
		player.throw_projectile((target - player.body_shape.global_position).normalized())
		for index in 16:
			player._physics_process(STEP)
		assert(player.projectile_stuck)
		assert(player.try_teleport() and player.ceiling_hang)
		var angle := PI * 0.5 if horizontal >= 0 else -PI * 0.5
		assert(is_equal_approx(player.body_shape.rotation, angle))
		var center: Vector2 = player.body_shape.global_position
		assert(absf(center.y - (-100 + 6.4 + 0.24)) < 0.01)
		var corners := PackedVector2Array()
		for unit in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(player.body_shape.global_transform * (unit * player.body_size * 0.5))
		var bounds := Rect2(corners[0], Vector2.ZERO)
		for point in corners:
			bounds = bounds.expand(point)
		assert(bounds.size.is_equal_approx(Vector2(44.8, 12.8)))
		for index in 60:
			player._physics_process(STEP)
		assert(player.ceiling_hang and player.body_shape.global_position.is_equal_approx(center))
		assert(player.sprite.clip_name == "climb_ceiling")
		assert(player.facing == (-1.0 if horizontal > 0 else 1.0))
		var frame_key: String = player.sprite.clips.climb_ceiling.frames[0][1]
		player.sprite.elapsed = 0
		player.sprite._refresh_frame()
		var pixel_offset := Assets.vec(Assets.sprite_info(frame_key).offset)
		pixel_offset.x *= player.facing
		var gfx: Dictionary = player.tuning.gfx_offset
		var source_offset: Vector2 = Vector2(gfx.x, -float(gfx.y)) * player.units
		var expected: Vector2 = center + (source_offset + pixel_offset).rotated(angle)
		assert(player.sprite.global_position.is_equal_approx(expected))
		assert(
			player.sprite.global_transform.x.is_equal_approx(
				Vector2.RIGHT.rotated(angle) * player.facing
			)
		)
		assert(player.sprite.global_transform.y.is_equal_approx(Vector2.DOWN.rotated(angle)))
		if DisplayServer.get_name() != "headless":
			camera.position = center
			camera.force_update_scroll()
			await RenderingServer.frame_post_draw
			Capture.save_png(root, "res://tmp/art-direction/ceiling-%d.png" % int(horizontal))
		player._jump(0)
		assert(not player.ceiling_hang and player.body_shape.rotation == 0)
		assert(player.sprite.body_rotation == 0)
		assert(absf(player.body_shape.global_position.y - center.y - 22.4) < 0.01)
	# If the middle probe misses, either end can catch a small ceiling segment.
	for edge in [-22.4, 22.4]:
		await _reset()
		_box(Rect2(edge - 1, -120, 2, 20))
		await _flush()
		player.position = Vector2(0, -54.96)
		player.ceiling_hang = true
		assert(player.ceiling.attach(Vector2(-60, 0)))
		assert(absf(player.body_shape.global_position.y + 93.36) < 0.01)
	# Rotating into Ground/Wall rejects the ceiling pose before the up probes.
	await _reset()
	_box(Rect2(15, -90, 5, 20))
	await _flush()
	player.position = Vector2(0, -54.96)
	player.ceiling_hang = true
	assert(not player.ceiling.attach(Vector2(-60, 0)))
	player.ceiling_hang = false
	assert(player.body_shape.rotation == 0 and player.sprite.body_rotation == 0)
	# Release is clamped by a nearby floor, rather than passing through it.
	await _reset()
	_box(Rect2(-100, -120, 200, 20))
	_box(Rect2(-100, -52, 200, 10))
	await _flush()
	player.position = Vector2(0, -54.96)
	player.ceiling_hang = true
	assert(player.ceiling.attach(Vector2(-60, 0)))
	player._jump(0)
	assert(absf(player.position.y + 52.24) < 0.01)
	# Restoring pose for respawn must not add the release offset to the checkpoint.
	await _reset()
	player.body_shape.rotation = PI * 0.5
	player.sprite.body_rotation = PI * 0.5
	player.ceiling_hang = true
	player.checkpoint = Vector2(31, 17)
	player.respawn()
	assert(player.position == player.checkpoint and player.body_shape.rotation == 0)
	assert(player.sprite.body_rotation == 0 and not player.ceiling_hang)
	player.queue_free()
	await _flush()
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	var checked := 0
	for body in lab.stage.get_children():
		if body is CollisionObject2D and body.has_meta("source_layer"):
			var expected_layer: bool = body.get_meta("source_layer") in ["Ground", "Wall"]
			assert(bool(body.collision_layer & Collision.STUCK_SURFACE) == expected_layer)
			checked += 1
	assert(checked > 0)
	print("CEILING_PASS source_colliders=", checked)
	quit()


func _reset() -> void:
	for child in terrain.get_children():
		child.queue_free()
	await _flush()
	player.checkpoint = Vector2.ZERO
	player.respawn()
	player.action_state = ""
	player.facing = 1
	player.source_time_scale = 1
	player._clear_move_contacts()
	player.move_and_slide()
	await _flush()


func _box(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Collision.SOLID | Collision.STUCK_SURFACE | Collision.PROJECTILE_SURFACE
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
