extends SceneTree
## Real collider queries, native buffer boundaries, input routing and gamepad snap.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var player: Node
var targeting: RefCounted
var first: Node
var second: Node
var start := Vector2(-20000, -20000)


func _initialize() -> void:
	call_deferred("run")


func frames(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func place_player(center: Vector2) -> void:
	player.position = center - player.body_shape.position


func tick(mouse: Vector2) -> void:
	targeting.step(mouse)


func pad(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = value
	Input.parse_input_event(event)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	player = lab.player
	targeting = player.targeting
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
	first = lab.stage.enemies[0]
	second = lab.stage.enemies[1]
	var positions: Dictionary = {first: first.position, second: second.position}
	first.position = start + Vector2(80, 0)
	second.position = start + Vector2(220, 0)
	for enemy: Node in [first, second]:
		enemy.weakpoint_presentation.range_active = true
		enemy.weakpoint_presentation.range_scale = 1.75
		enemy.kunai.weak_points = 1
		enemy._sync_visuals()
	place_player(start)
	player.clock = 10.0
	await frames()
	tick(first.position)
	assert(targeting.current == first)
	assert(first.weakpoint_presentation.outline.selected)
	first.weakpoint_presentation.outline.step(float(first.data.common.OutLineSpeed))
	for go in first.weakpoint_presentation.outline.values:
		assert(
			is_equal_approx(
				float(first.visuals[go].material.get_shader_parameter("base_outline_alpha")), 1.0
			)
		)
	var deadline: float = targeting.buffer_until
	assert(is_equal_approx(deadline - player.clock, 0.06))
	var miss := start + Vector2(0, -500)
	player.clock = deadline
	tick(miss)
	assert(targeting.current == first, "The native deadline comparison is strict")
	player.clock += 0.000001
	tick(miss)
	assert(targeting.current == null)
	assert(not first.weakpoint_presentation.outline.selected)

	tick(first.position)
	place_player(start + Vector2(450, 0))
	await frames()
	assert(not first.weakpoint_presentation._contact() and second.weakpoint_presentation._contact())
	tick(miss)
	assert(targeting.current == first, "Any remaining range keeps the mouse buffer alive")
	place_player(start - Vector2(800, 0))
	await frames()
	tick(first.position)
	assert(targeting.current == null, "Leaving all ranges bypasses the mouse buffer")

	place_player(start)
	await frames()
	var wall := StaticBody2D.new()
	wall.position = start + Vector2(40, 0)
	wall.collision_layer = Collision.SIGHT_SURFACE
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 120)
	collider.shape = rectangle
	wall.add_child(collider)
	lab.viewport.add_child(wall)
	await frames()
	player.clock += 1.0
	tick(first.position)
	assert(targeting.current == null, "A source sight wall prevents selection")
	wall.collision_layer = Collision.ONE_WAY
	await frames()
	tick(first.position)
	assert(targeting.current == first, "IgnorePlatform excludes one-way platforms")
	wall.queue_free()
	await frames()
	tick(second.position)
	assert(targeting.current == second)
	assert(not first.weakpoint_presentation.outline.selected)
	assert(second.weakpoint_presentation.outline.selected)

	# Real root input travels through the lab into its standalone SubViewport.
	pad(1.0)
	await frames()
	assert(targeting.using_gamepad and targeting.stick.x == 1.0)
	tick(miss)
	assert(targeting.snap_target == first and targeting.current == first)
	var motion := InputEventMouseMotion.new()
	lab._input(motion)
	assert(targeting.using_gamepad, "Native device tracking ignores mouse motion")
	pad(0.0)
	await frames()
	tick(miss)
	assert(targeting.snap_target == first, "Releasing the stick retains a valid snap")
	first.position = start + Vector2(1700, 0)
	await frames()
	tick(miss)
	assert(targeting.snap_target == null and targeting.current == null)
	tick(miss)
	assert(
		targeting.snap_target == second,
		"A released stick reacquires in the facing direction next update"
	)
	second.position = start + Vector2(220, 40)
	await frames()
	tick(miss)
	assert(player._aim_direction(true).is_equal_approx(Vector2(220, 40).normalized()))
	targeting._check_snap(Vector2.LEFT)
	assert(targeting.snap_target == null)
	player.clock = targeting.aim_until
	tick(miss)
	assert(targeting.snap_target == null, "Snap acquisition requires a live aim timer")
	pad(1.0)
	await frames()
	tick(miss)
	assert(targeting.snap_target == second)
	second.weakpoint_presentation.range_active = false
	tick(miss)
	assert(
		targeting.current == null and targeting.snap_target == second,
		"Throw snap can exist outside weak-point range"
	)
	second.weakpoint_presentation.range_active = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await frames()
	assert(not targeting.using_gamepad)
	tick(second.position)
	assert(targeting.current == second and targeting.snap_target == null)
	key.pressed = false
	Input.parse_input_event(key)
	player.die(true)
	assert(targeting.current == null and not second.weakpoint_presentation.outline.selected)
	player.respawn()
	assert(targeting.current == null and targeting.buffer_until == 0.0)

	for enemy: Node in positions:
		enemy.position = positions[enemy]
		enemy.weakpoint_presentation.range_active = false
		enemy._sync_visuals()
	if DisplayServer.get_name() != "headless":
		await capture_factory()
	# Unity's destroyed target compares equal to null. A freed Godot reference
	# may remain in the registry until its owner removes it; skip it safely.
	targeting.enemies = lab.stage.enemies.duplicate()
	targeting._set_current(first)
	lab.stage.enemies.erase(first)
	first.queue_free()
	await frames()
	tick(miss)
	assert(targeting.current == null)
	lab.queue_free()
	await process_frame
	print("WEAK_POINT_TARGETING_PASS")
	quit()


func capture_factory() -> void:
	var bow: Node
	for enemy: Node in lab.stage.enemies:
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	bow.weakpoint_presentation.hit(1)
	bow.kunai.weak_points = 1
	place_player(bow.position + Vector2(90, 0))
	await frames(45)
	bow.weakpoint_presentation.step(0.0)
	tick(bow.position)
	assert(targeting.current == bow)
	# The frozen actor needs a second native update to calculate the newly
	# selected target's line endpoints (selection follows line calculation).
	tick(bow.position)
	bow.weakpoint_presentation.outline.step(float(bow.data.common.OutLineSpeed))
	# Respawn leaves this frozen test actor on a red source birth frame. Use a
	# stable idle pose so those birth pixels cannot be mistaken for target effects.
	player.sprite.play("idle", true)
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/art-direction/inari_target_selection.png")
