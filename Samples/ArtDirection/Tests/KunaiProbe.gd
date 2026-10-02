extends SceneTree
## Real throw input, moving attachment, enemy teleport cost/damage and input buffer.

var lab: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	var enemy: Node = await _setup()
	await _throw_at(enemy)
	await _frames(8)
	var player: Node = lab.player
	assert(player.projectile_target == enemy and player.projectile_stuck)
	assert(enemy.health == 280.0, "Source stuck damage is zero")
	await _capture("kunai-attached")
	var local: Transform2D = player.projectile_local_pose
	enemy.position.x += 24.0
	enemy.facing = -1.0
	await _frames(2)
	assert(
		player.projectile.global_transform.is_equal_approx(
			enemy.kunai.attachment_transform() * local
		)
	)
	var target: Vector2 = enemy.kunai.destination(player)
	# On an uninterrupted flat platform the source ground-edge probe starts at
	# the enemy's forward edge, then accounts for the player's half-width.
	var expected_x: float = (
		enemy.position.x + enemy.body_shape.shape.size.x * 0.5 + 96.0 - player.body_size.x * 0.5
	)
	assert(absf(target.x - expected_x) < 0.1)
	player.stamina = 19.0
	assert(not player.try_teleport(), "Enemy teleport needs 20 stamina")
	assert(enemy.health == 280.0 and enemy.kunai.weak_points == 0)
	player.stamina = 20.0
	assert(player.try_teleport())
	assert(lab.camera_rig.impulse.event_name == "ShurikenDash")
	assert(player.stamina == 0.0 and enemy.health == 230.0)
	assert(enemy.kunai.weak_points == 1 and enemy.kunai.reset_time == 5.0)
	assert((player.global_position + player.body_shape.position).distance_to(target) < 0.1)
	assert(not player.climbing and not player.ceiling_hang and player.can_air_jump)
	assert(not player.projectile_active)
	await _capture("kunai-teleport")
	await _frames(302)
	assert(enemy.kunai.weak_points == 0, "Source weak-point timer must expire")

	enemy = await _setup()
	player = lab.player
	await _throw_at(enemy)
	assert(not player.projectile_stuck)
	Input.action_press(player.input_action("teleport"))
	await _frames(2)
	Input.action_release(player.input_action("teleport"))
	await _frames(10)
	assert(enemy.health == 230.0 and not player.projectile_active, "Pre-impact Q buffer was lost")

	# Death removes an attached target instead of leaving a stale teleport point.
	enemy = await _setup()
	player = lab.player
	await _throw_at(enemy)
	await _frames(8)
	assert(player.projectile_target == enemy)
	enemy.receive_study_hit({"Damage": 1000.0}, 1.0)
	await _frames(2)
	assert(not player.projectile_active and player.projectile_target == null)

	# Lethal kunai impact replaces the generic teleport wave with its kill wave.
	enemy = await _setup()
	player = lab.player
	enemy.health = 49.0
	await _throw_at(enemy)
	await _frames(8)
	assert(player.try_teleport())
	assert(enemy.dead and lab.camera_rig.impulse.event_name == "ShurikenDashDie")
	lab.queue_free()
	await process_frame
	print("KUNAI_PROBE_PASS")
	quit()


func _setup() -> Node:
	lab.load_level(0)
	var bow: Node
	for enemy: Node in lab.stage.enemies:
		enemy.patrol.enabled = false
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	await _frames(20)
	lab.player.position = bow.position + Vector2(-100, 32)
	lab.player.velocity = Vector2.ZERO
	await _frames(12)
	return bow


func _throw_at(enemy: Node) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = (
		lab.viewport.get_canvas_transform() * (enemy.global_position + enemy.body_shape.position)
	)
	lab.viewport.push_input(motion, true)
	Input.action_press(lab.player.input_action("throw"))
	await _frames(2)
	Input.action_release(lab.player.input_action("throw"))


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/art-direction/" + name + ".png")
