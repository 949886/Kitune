extends SceneTree
## Actual source assets and ray geometry for native free/enemy gamepad aim.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")


class TargetFixture:
	extends Node2D
	var body_shape := CollisionShape2D.new()


func _initialize() -> void:
	call_deferred("run")


func wall(point: Vector2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = point
	body.collision_layer = layer
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 160)
	collider.shape = shape
	body.add_child(collider)
	return body


func axes(value: Vector2) -> void:
	for axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = value.x if axis == JOY_AXIS_RIGHT_X else value.y
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var source: Dictionary = Assets.read_json(Assets.ROOT + "gamepad_aim.json")
	var mouse: Dictionary = Assets.read_json(Assets.ROOT + "target_marker.json")
	assert(source.programs.Mat_dotline == mouse.programs.Mat_dotline)
	assert(source.minimum_hit_distance == 5.0)
	assert(source.line.parameters.colorGradient.key0.r == 1.0)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	player.position = Vector2(-20000, -20000)
	player.clock = 10.0
	var targeting: RefCounted = player.targeting
	targeting.enemies = []
	var aim: Node = targeting.gamepad_aim
	axes(Vector2.RIGHT)
	targeting.step(Vector2.ZERO)
	assert(aim.visible and not aim.pointer.visible)
	assert(
		aim.line.points[1].is_equal_approx(
			Vector2(player.combat.ShurikenMaxDistance * player.units, 0)
		)
	)
	assert(aim.line.global_position.is_equal_approx(aim.holder_position + Vector2(32, 0)))
	var near := wall(aim.holder_position + Vector2(64, 0), Collision.SIGHT_SURFACE)
	lab.stage.add_child(near)
	await physics_frame
	targeting.step(Vector2.ZERO)
	assert(aim.line.points[1] == Vector2.ZERO and not aim.pointer.visible)
	near.position = aim.holder_position + Vector2(88, 0)
	await physics_frame
	targeting.step(Vector2.ZERO)
	assert(
		aim.line.points[1] == Vector2.ZERO and not aim.pointer.visible,
		"Exactly five source units stays collapsed"
	)
	near.position.x += 136
	await physics_frame
	targeting.step(Vector2.ZERO)
	assert(aim.pointer.visible and aim.pointer.modulate == Color.WHITE)
	assert(absf(aim.pointer.global_position.x - (near.position.x - 8)) < 0.02)
	var endpoint: Vector2 = aim.pointer.global_position
	assert((aim.line.global_position + aim.line.points[1]).is_equal_approx(endpoint))
	# Platform is omitted from IgnorePlatform, even when it is closer than Ground.
	var platform := wall(aim.holder_position + Vector2(48, 0), Collision.ONE_WAY)
	lab.stage.add_child(platform)
	await physics_frame
	targeting.step(Vector2.ZERO)
	assert(aim.pointer.global_position.is_equal_approx(endpoint))
	lab.water_capture._process(0.0)
	var reflected: Node2D
	for pair: Dictionary in lab.water_capture.marker_pairs:
		if pair.source == aim.pointer:
			reflected = pair.copy
	assert(reflected != null and reflected.visible)
	assert(reflected.global_transform == aim.pointer.global_transform)
	assert(reflected.modulate == aim.pointer.modulate)
	if DisplayServer.get_name() != "headless":
		await verify_gpu(lab, aim, reflected)
	var target := TargetFixture.new()
	var shape := target.body_shape
	target.add_child(shape)
	lab.stage.add_child(target)
	target.position = aim.holder_position + Vector2(200, -100)
	shape.position = Vector2(0, -20)
	targeting.snap_target = target
	targeting.aim_until = player.clock - 1.0
	targeting.pad_direction = (target.position - aim.holder_position).normalized()
	aim.update_aim(targeting)
	assert(aim.pointer.visible and aim.pointer.modulate == Color.YELLOW)
	assert(aim.pointer.global_position.is_equal_approx(target.position + shape.position))
	targeting.snap_target = null
	targeting.aim_until = player.clock
	aim.update_aim(targeting)
	assert(not aim.visible)
	targeting.using_gamepad = false
	targeting.aim_until = player.clock + 1.0
	aim.update_aim(targeting)
	assert(not aim.visible)
	targeting.using_gamepad = true
	aim.update_aim(targeting)
	assert(aim.visible)
	targeting.reset()
	assert(not aim.visible)
	lab.queue_free()
	await process_frame
	print("GAMEPAD_AIM_PASS")
	quit()


func verify_gpu(lab: Node, aim: Node, reflected: Node2D) -> void:
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	var capture: Node = lab.water_capture
	for collection: Array in [capture.stage_pairs, capture.actor_pairs, capture.marker_pairs]:
		for pair: Dictionary in collection:
			pair.copy.visible = pair.copy == reflected
	var reflected_line: Line2D
	for pair: Dictionary in capture.line_pairs:
		pair.copy.visible = pair.source == aim.line
		if pair.source == aim.line:
			reflected_line = pair.copy
	capture.particles.hide()
	capture.camera.position = aim.holder_position + Vector2(100, 0)
	capture.camera.force_update_scroll()
	reflected_line.hide()
	await draw_frames()
	var pointer_pixels: Image = capture.viewport.get_texture().get_image()
	assert(pointer_pixels.get_used_rect().size != Vector2i.ZERO)
	reflected.hide()
	reflected_line.show()
	await draw_frames()
	var line_pixels: Image = capture.viewport.get_texture().get_image()
	assert(line_pixels.get_used_rect().size != Vector2i.ZERO)
	reflected_line.hide()
	await draw_frames()
	assert(capture.viewport.get_texture().get_image().get_used_rect().size == Vector2i.ZERO)
	reflected.show()
	reflected_line.show()
	await draw_frames()
	capture.viewport.get_texture().get_image().save_png(
		"res://tmp/art-direction/inari_gamepad_aim.png"
	)
	print(
		"GAMEPAD_AIM_GPU pointer=",
		pointer_pixels.get_used_rect(),
		" line=",
		line_pixels.get_used_rect()
	)
	lab.process_mode = Node.PROCESS_MODE_INHERIT


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
