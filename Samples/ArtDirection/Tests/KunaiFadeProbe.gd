extends SceneTree
## Native two-tween lifecycle, continued motion, attachment and water reflection.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var retired: Array[Node] = []


func _initialize() -> void:
	call_deferred("run")


func pause_fade(fade: Node) -> void:
	fade.set_process(false)
	fade.set_physics_process(false)
	retired.append(fade)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	player.position = Vector2(-20000, -20000)
	lab.stage.kunai_retired.connect(pause_fade)
	player.throw_projectile(Vector2.RIGHT)
	var origin: Vector2 = player.projectile.global_position
	player.throw_projectile(Vector2.LEFT)
	assert(retired.size() == 1 and player.projectile_active)
	var fade: Node = retired[0]
	assert(fade.visible and fade.global_position == origin)
	assert(fade.material != player.projectile.material)
	assert(fade.velocity.x > 0.0 and player.projectile_velocity.x < 0.0)
	assert(fade.scale.is_equal_approx(Vector2(0.8, 0.8)))
	fade.advance_fade(0.1)
	assert(absf(fade.material.get_shader_parameter("hit_blend") - 0.75) < 0.00001)
	assert(fade.modulate.a == 1.0)
	lab.stage.combat_clock.stop_frames(60, 1.0 / 60.0)
	fade.advance_motion(0.05)
	fade.advance_fade(0.1)
	assert(fade.global_position.x > origin.x and fade.phase == "fade")
	assert(fade.modulate.a == 1.0, "New fade tween starts on the next update")
	if DisplayServer.get_name() != "headless":
		await verify_gpu(fade)
	else:
		fade.advance_fade(0.1)
	assert(absf(fade.modulate.a - 0.25) < 0.00001)
	lab.water_capture.projectiles.sync()
	var mirror: Sprite2D = lab.water_capture.projectiles.kunai_pairs[fade.get_instance_id()].copy
	assert(mirror.global_transform == fade.global_transform)
	assert(mirror.modulate == fade.modulate and mirror.z_index == fade.z_index)
	assert(mirror.material != fade.material)
	assert(mirror.material.get_shader_parameter("hit_blend") == 1.0)
	fade.advance_fade(0.1)
	lab.water_capture.projectiles.sync()
	assert(fade.phase == "done" and not mirror.visible)
	assert(not lab.water_capture.projectiles.kunai_pairs.has(fade.get_instance_id()))
	assert(player.projectile_active and player.projectile.visible)
	assert(player.projectile.material.get_shader_parameter("hit_blend") == 0.0)
	await process_frame
	lab.stage.combat_clock.reset()
	# Clear while Throw is ignored; the same input in Idle dequeues immediately.
	Input.action_press(player.input_action("cancel_projectile"))
	player._read_actions(0.0, 0.0)
	assert(player.projectile_active and retired.size() == 1)
	player.action_state = ""
	player._read_actions(0.0, 0.0)
	Input.action_release(player.input_action("cancel_projectile"))
	assert(not player.projectile_active and not player.projectile.visible)
	assert(not player.try_teleport())
	assert(retired.size() == 2)
	var flying: Node = retired[1]
	var before: Vector2 = flying.global_position
	flying.advance_motion(0.5)
	assert(
		(
			flying.global_position.distance_to(before)
			> player.combat.ShurikenMaxDistance * player.units
		)
	)
	flying.finish()
	# A retiring blade still collides, but it cannot become a teleport target again.
	player.throw_projectile(Vector2.RIGHT)
	player._retire_projectile()
	var collision_fade: Node = retired.back()
	var wall := StaticBody2D.new()
	wall.collision_layer = Collision.PROJECTILE_SURFACE
	wall.set_meta("source_layer", "Ground")
	wall.position = collision_fade.global_position + Vector2(50, 0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 100)
	shape.shape = rectangle
	wall.add_child(shape)
	lab.stage.add_child(wall)
	await physics_frame
	collision_fade.advance_motion(0.1)
	assert(collision_fade.stuck and collision_fade.velocity == Vector2.ZERO)
	assert(absf(collision_fade.global_position.x - (wall.position.x - 5.0)) < 0.01)
	assert(not player.projectile_active)
	var stopped: Vector2 = collision_fade.global_position
	collision_fade.advance_motion(0.1)
	assert(collision_fade.global_position == stopped)
	collision_fade.finish()
	# Already attached fades keep the enemy's current attachment transform.
	lab.load_level(0)
	await process_frame
	player = lab.player
	player.set_physics_process(false)
	lab.stage.kunai_retired.connect(pause_fade)
	var enemy: Node = lab.stage.enemies[0]
	enemy.set_physics_process(false)
	player.throw_projectile(Vector2.RIGHT)
	player.projectile_target = enemy
	player.projectile_stuck = true
	player.projectile_local_pose = (
		enemy.kunai.attachment_transform().affine_inverse() * player.projectile.global_transform
	)
	player._retire_projectile()
	var attached: Node = retired.back()
	enemy.position.x += 25.0
	enemy.facing *= -1
	attached.advance_motion(0.1)
	assert(
		attached.global_transform == enemy.kunai.attachment_transform() * attached.attachment_pose
	)
	# Float accumulation keeps the native 60 Hz two-phase duration at 24 ticks.
	for step in 23:
		attached.advance_fade(1.0 / 60.0)
	assert(attached.phase == "fade")
	attached.advance_fade(1.0 / 60.0)
	assert(attached.phase == "done")
	lab.queue_free()
	await process_frame
	print("KUNAI_FADE_PASS")
	quit()


func verify_gpu(fade: Node) -> void:
	var capture: Node = lab.water_capture
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	for collection: Array in [
		capture.stage_pairs, capture.actor_pairs, capture.line_pairs, capture.marker_pairs
	]:
		for entry: Dictionary in collection:
			entry.copy.hide()
	capture.particles.hide()
	capture.camera.position = fade.global_position
	capture.camera.force_update_scroll()
	capture.projectiles.sync()
	await draw_frames()
	var opaque: Image = capture.viewport.get_texture().get_image()
	var opaque_alpha := peak_alpha(opaque)
	assert(opaque_alpha > 0.5, "Retiring kunai must render into the actual water target")
	fade.advance_fade(0.1)
	capture.projectiles.sync()
	await draw_frames()
	var faded: Image = capture.viewport.get_texture().get_image()
	var ratio := peak_alpha(faded) / opaque_alpha
	assert(absf(ratio - 0.25) < 0.01, "Water reflection must retain the native fade alpha")
	faded.save_png("res://tmp/art-direction/inari_kunai_fade_water.png")
	print("KUNAI_FADE_GPU alpha_ratio=", ratio)
	lab.process_mode = Node.PROCESS_MODE_INHERIT


func peak_alpha(image: Image) -> float:
	var peak := 0.0
	var rect := image.get_used_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			peak = maxf(peak, image.get_pixel(x, y).a)
	return peak


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
