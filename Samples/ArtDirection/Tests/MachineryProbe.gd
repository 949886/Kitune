extends SceneTree
## Native source scene plus real controller inputs. Independent motion checks use
## known quarter/midpoint easing values; geometry fixtures retain shipped shapes.

const Platform = preload("res://Samples/ArtDirection/Runtime/InariMovingPlatform.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var player: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2)
	player = lab.player
	await frames(60)
	assert(player.is_on_floor())
	if DisplayServer.get_name() != "headless" and "--capture-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		lab.viewport.get_texture().get_image().save_png(
			"res://Samples/ArtDirection/Previews/inari_machinery.png"
		)
	var machinery: Node = lab.stage.machinery
	assert(machinery.platforms.size() == 2 and machinery.levers.size() == 2)
	assert(lab.stage.source_checkpoints.size() == 2 and lab.stage.spike_hazards.size() == 1)
	var horizontal: Node = machinery.platforms.values()[0]
	var vertical: Node = machinery.platforms.values()[1]
	var lever: Node = machinery.levers[0]
	assert(horizontal.visuals.size() == 35 and vertical.visuals.size() == 35)
	assert(horizontal.lights.size() == 2 and horizontal.wheels.size() == 2)
	var visual_start: Vector2 = horizontal.visuals[0].position
	var platform_start: Vector2 = horizontal.position
	assert(lever.targets == [horizontal])
	assert(not lever.receive_study_hit({"interaction": 2}, 1.0))
	assert(not lever.receive_study_hit({"interaction": 64}, 1.0))
	assert(horizontal.stopped)
	# Start from the actual entrance and attack the lever through player input.
	Input.action_press(player.input_action("attack"))
	await frames(1)
	Input.action_release(player.input_action("attack"))
	await frames(25)
	assert(lever.switched_on and not horizontal.stopped)
	assert(lab.stage.audio.last_selection.has("lever"))
	Input.action_press(player.input_action("jump"))
	Input.action_press(player.input_action("right"))
	var boarded := false
	var boarded_offset := 0.0
	for frame in 190:
		await frames(1)
		if frame == 18:
			Input.action_release(player.input_action("jump"))
		if player.is_on_floor() and frame > 5:
			Input.action_release(player.input_action("right"))
			if not boarded:
				boarded = true
				boarded_offset = player.position.x - horizontal.position.x
		if boarded:
			assert(not player.dead)
			assert(absf(player.position.x - horizontal.position.x - boarded_offset) < 0.05)
	Input.action_release(player.input_action("right"))
	assert(boarded and horizontal.stopped)
	assert(horizontal.position.distance_to(horizontal.waypoints[1]) < 0.002)
	assert(player.position.x > 14000.0)
	assert(lab.completed)
	assert(
		(
			(horizontal.visuals[0].position - visual_start).distance_to(
				horizontal.position - platform_start
			)
			< 0.01
		)
	)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/machinery-ride-verified.png"
		)
	# Gallery pauses the whole mechanism clock, not just the player's input.
	horizontal.activate()
	lab.show_gallery()
	var clock: float = horizontal.clock
	await frames(20)
	assert(horizontal.clock == clock)
	lab.gallery.hide()
	lab.set_controls_enabled(true)
	player.set_physics_process(false)
	lab.set_physics_process(false)
	for platform: Node in machinery.platforms.values():
		platform.set_physics_process(false)
	await _check_motion(horizontal.source)
	await _check_passengers(horizontal.source, vertical.source)
	await _check_kunai(vertical.source)
	await _check_crushing(horizontal.source)
	var previous: WeakRef = weakref(horizontal)
	await _check_vertical_route()
	assert(previous.get_ref() == null)
	previous = weakref(lab.stage.machinery.platforms.values()[1])
	lab.load_level(0)
	await frames(2)
	assert(previous.get_ref() == null and lab.stage.machinery.platforms.is_empty())
	lab.queue_free()
	await frames(2)
	print("MACHINERY_PROBE_PASS")
	quit()


func _check_vertical_route() -> void:
	# Select the second practice entrance through the same signal as its button.
	lab.practice_selector.get_child(1).pressed.emit()
	lab.set_physics_process(true)
	player = lab.player
	await frames(60)
	assert(lab.practice_entry == 1 and player.is_on_floor())
	var wall: Node = lab.stage.machinery.platforms.values()[1]
	Input.action_press(player.input_action("attack"))
	await frames(1)
	Input.action_release(player.input_action("attack"))
	await frames(25)
	assert(not wall.stopped)
	Input.action_press(player.input_action("right"))
	await frames(10)
	Input.action_release(player.input_action("right"))
	await frames(1)
	var mouse := InputEventMouseMotion.new()
	mouse.position = (
		lab.viewport.get_canvas_transform()
		* (player.body_shape.global_position + Vector2.RIGHT * 100.0)
	)
	lab.viewport.push_input(mouse, true)
	Input.action_press(player.input_action("throw"))
	await frames(1)
	Input.action_release(player.input_action("throw"))
	await frames(12)
	assert(player.projectile_stuck and player.projectile_surface.get_ref() == wall)
	Input.action_press(player.input_action("teleport"))
	await frames(1)
	Input.action_release(player.input_action("teleport"))
	await frames(2)
	assert(player.climbing)
	var relative_y: float = player.position.y - wall.position.y
	for frame in 240:
		await frames(1)
		assert(not player.dead and player.climbing)
		# The source route crosses a one-way ledge. Its corner must not cause
		# side collision, shift the player outward or break the moving wall hold.
		assert(absf(player.position.y - wall.position.y - relative_y) < 0.02)
	assert(wall.stopped and wall.arrival_count == 1)
	assert(player.position.y < 3264.0 and lab.completed)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/machinery-vertical-verified.png"
		)


func fixture(record: Dictionary, origin: Vector2) -> Node:
	var data := record.duplicate(true)
	data.transform[4] = origin.x
	data.transform[5] = origin.y
	var platform := Platform.new()
	platform.configure(data, player, [])
	lab.stage.add_child(platform)
	platform.set_physics_process(false)
	return platform


func _check_motion(record: Dictionary) -> void:
	player.position = Vector2(-25000, -15000)
	var platform: Node = fixture(record, Vector2(-22000, -10000))
	var start: Vector2 = platform.position
	var distance: float = platform.waypoints[0].distance_to(platform.waypoints[1])
	var duration: float = distance / (platform.source.fields.Speed * 16.0)
	platform.activate()
	platform.advance(0.5)
	assert(platform.position == start)
	platform.on_source_time_scale(0.0)
	platform.advance(1.0)
	assert(platform.position == start and platform.progress == 0.0)
	platform.on_source_time_scale(0.5)
	platform.advance(duration / 2.0)
	var quarter := 1.0 / (1.0 + sqrt(27.0))
	assert(absf((platform.position.x - start.x) / distance - quarter) < 0.00002)
	var before: Vector2 = platform.position
	platform.activate()
	platform.advance(0.0)
	assert(platform.position.distance_to(before) < 0.002, "Reversal must be continuous")
	platform.on_source_time_scale(1.0)
	platform.advance(duration)
	assert(platform.stopped and platform.position.distance_to(start) < 0.002)
	platform.queue_free()
	await frames(2)


func _check_passengers(horizontal: Dictionary, vertical: Dictionary) -> void:
	for record: Dictionary in [horizontal, vertical]:
		var platform: Node = fixture(record, Vector2(-20000, -10000))
		var surface: Rect2 = platform.global_transform * platform.bounds
		player.position = Vector2(surface.get_center().x, surface.position.y - player.safe_margin)
		player.velocity = Vector2.ZERO
		player.climbing = false
		await frames(2)
		var before: Vector2 = player.position
		var start: Vector2 = platform.position
		platform.activate()
		platform.clock = platform.next_move
		platform.advance(0.1)
		assert((player.position - before).distance_to(platform.position - start) < 0.002)
		platform.queue_free()
		await frames(2)
	var wall: Node = fixture(vertical, Vector2(-21000, -10000))
	var box: Rect2 = wall.global_transform * wall.bounds
	player.position = Vector2(
		box.position.x - player.body_size.x / 2.0 - player.safe_margin,
		box.get_center().y + player.body_size.y / 2.0
	)
	player.climbing = true
	await frames(2)
	var before: Vector2 = player.position
	var start: Vector2 = wall.position
	wall.activate()
	wall.clock = wall.next_move
	wall.advance(0.1)
	assert(
		(player.position - before).distance_to(wall.position - start) < 0.002,
		"Clinging passenger lost its carrier"
	)
	wall.queue_free()
	player.climbing = false
	await frames(2)


func _check_kunai(record: Dictionary) -> void:
	var platform: Node = fixture(record, Vector2(-20000, -10000))
	var surface: Rect2 = platform.global_transform * platform.bounds
	player.position = surface.get_center() + Vector2(-100, player.body_size.y / 2.0)
	player.action_state = ""
	await frames(2)
	player.throw_projectile(Vector2.RIGHT)
	for frame in 12:
		player._update_projectile(1.0 / 60.0)
		if player.projectile_stuck:
			break
	assert(player.projectile_stuck and player.projectile_surface.get_ref() == platform)
	var local: Vector2 = platform.to_local(player.projectile.global_position)
	platform.activate()
	platform.clock = platform.next_move
	platform.advance(0.1)
	player._update_projectile(0.0)
	assert(platform.to_local(player.projectile.global_position).distance_to(local) < 0.002)
	assert(
		player.try_teleport() and player.climbing,
		"Moving wall must remain a valid teleport/climb target"
	)
	assert(not player.projectile_active and player.projectile_surface == null)
	platform.queue_free()
	await frames(2)


func _check_crushing(record: Dictionary) -> void:
	# A real collision query must stop a side-pushed actor at the static wall,
	# then invoke the source OnStuck kill rather than tunnel through the wall.
	var platform: Node = fixture(record, Vector2(-22000, -10000))
	var box: Rect2 = platform.global_transform * platform.bounds
	player.position = Vector2(
		box.end.x + player.body_size.x / 2.0 + player.safe_margin,
		box.get_center().y + player.body_size.y / 2.0
	)
	player.climbing = false
	player.velocity = Vector2.ZERO
	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = Collision.SOLID
	obstacle.position = (
		player.position + Vector2(player.body_size.x / 2.0 + 6.0, -player.body_size.y / 2.0)
	)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 100.0)
	shape.shape = rectangle
	obstacle.add_child(shape)
	lab.stage.add_child(obstacle)
	await frames(2)
	platform.activate()
	platform.clock = platform.next_move
	platform.advance(0.1)
	assert(player.dead, "A solid wall must crush the pushed passenger")
	platform.queue_free()
	obstacle.queue_free()
	await frames(2)
