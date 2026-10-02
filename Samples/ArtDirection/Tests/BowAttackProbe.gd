extends SceneTree
## Actual bow ready/confirm clips, post-animation aiming, frame-zero firing and melee.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var lab: Node
var bow: Node
var sequence: RefCounted
var shots: Array[Dictionary] = []
var clock := 0.0
var transitions: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func tick(delta := 1.0 / 60.0) -> void:
	clock += delta
	sequence.step(delta)
	bow.motion_animation.advance(delta)
	bow._sync_visuals()


func until(state: String, limit := 300) -> void:
	for frame in limit:
		if sequence.state == state:
			return
		tick()
	assert(false, "Bow attack failed to enter " + state)


func place_player(offset: Vector2) -> void:
	lab.player.position = sequence.center() + offset - lab.player.body_shape.position
	await physics_frame
	await process_frame


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	sequence = bow.bow_attack
	bow.motion_animation.set_process(false)
	assert(not sequence.settings.can_alarm and sequence.settings.run_away_weight == 80.0)
	assert(
		bow.data.profile.RunAwayWeight == 0.0,
		"AI must use the serialized bow field, not this unused profile value"
	)
	var origin: Vector2 = (
		bow.visuals[sequence.settings.anchor_go].global_transform
		* Assets.vec(sequence.settings.anchor_local)
	)
	assert(origin.distance_to(Assets.vec(sequence.settings.source_position)) < 0.001)
	sequence.arrow_launched.connect(
		func(arrow: Node2D):
			shots.append(
				{
					"point": arrow.global_position,
					"angle": arrow.rotation,
					"clock": clock,
					"state_elapsed": sequence.elapsed
				}
			)
			arrow.queue_free()
	)
	sequence.state_changed.connect(func(state: String): transitions[state] = clock)
	var original_position: Vector2 = bow.position
	bow.position = Vector2(-20000, -20000)
	bow._sync_visuals()
	await place_player(Vector2(240, -120))
	sequence.begin(lab.player, 0)
	assert(sequence.state == "ready" and not bow.ranged_presentation.aiming)
	assert(is_equal_approx(bow.motion_duration, 19.0 / 48.0))
	for frame in 23:
		tick()
	assert(not bow.ranged_presentation.aiming and shots.is_empty())
	tick()
	assert(bow.ranged_presentation.aiming and bow.ranged_presentation.angle > 0.0)
	until("confirm")
	assert(absf(transitions.confirm - 1.15) <= 1.0 / 60.0 + 0.0001)
	assert(is_equal_approx(bow.motion_duration, 0.1875))
	var locked_angle := float(bow.ranged_presentation.angle)
	var anchor_pose: Transform2D = bow.visuals[sequence.settings.anchor_go].global_transform
	var locked_origin := anchor_pose * Assets.vec(sequence.settings.anchor_local)
	await place_player(Vector2(20, 0))
	for frame in 10:
		tick()
		assert(
			(
				sequence.state == "confirm"
				and is_equal_approx(bow.ranged_presentation.angle, locked_angle)
			)
		)
	# A new zero-time authored attack replaces any previous incoming movement.
	var incoming_movement := {"Duration": 1.0}
	bow.knockback = incoming_movement
	until("attack")
	assert(bow.knockback.is_empty())
	assert(incoming_movement == {"Duration": 1.0}, "Do not mutate shared hit profiles")
	assert(shots.size() == 1 and shots[0].state_elapsed == 0.0)
	assert(shots[0].point.distance_to(locked_origin) < 0.002)
	assert(is_equal_approx(shots[0].angle, -deg_to_rad(locked_angle)))
	assert(not bow.ranged_presentation.aiming and bow.motion == "Attack:0")
	var shot_duration := float(bow.motion_duration)
	until("post")
	assert(bow.motion == "Attack:0" and is_equal_approx(bow.motion_duration, shot_duration))
	until("idle")
	assert(transitions.idle - transitions.post > shot_duration and shots.size() == 1)

	# A close player cancels Ready, while moving close during Confirm above did not cancel.
	await place_player(Vector2(240, 0))
	sequence.begin(lab.player, 0)
	await place_player(Vector2(24, 0))
	tick()
	assert(sequence.state == "cancel" and bow.motion == "AttackCancel:0")
	until("idle")
	assert(shots.size() == 1)

	# Selected melee uses its own clips and checks damage immediately at attack frame zero.
	var health := float(lab.player.damage.health)
	var start := clock
	sequence.begin(lab.player, 1)
	assert(is_equal_approx(bow.motion_duration, (11.0 / 60.0) / 0.9))
	until("confirm")
	assert(is_equal_approx(bow.motion_duration, 1.0 / 3.0))
	until("attack")
	assert(lab.player.damage.health == health - 1.0 and sequence.player_checked)
	until("post")
	assert(bow.motion == "Attack:1", "AttackState.Exit resets the Animator index before Post")
	until("idle")
	assert(lab.player.damage.health == health - 1.0 and clock - start < 1.5)
	assert(sequence.attack_index == 0 and shots.size() == 1)

	# Left-facing aiming rotates the source arm anchor before copying the arrow origin.
	await place_player(Vector2(-240, -100))
	sequence.begin(lab.player, 0)
	until("confirm")
	assert(bow.facing == -1.0)
	locked_angle = bow.ranged_presentation.angle
	locked_origin = (
		bow.visuals[sequence.settings.anchor_go].global_transform
		* Assets.vec(sequence.settings.anchor_local)
	)
	until("attack")
	assert(shots.size() == 2 and shots[-1].point.distance_to(locked_origin) < 0.002)
	var expected := Vector2(-cos(deg_to_rad(locked_angle)), -sin(deg_to_rad(locked_angle))).angle()
	assert(is_equal_approx(shots[-1].angle, expected))
	sequence.reset()
	if DisplayServer.get_name() != "headless":
		bow.position = original_position
		await place_player(Vector2(220, -80))
		sequence.begin(lab.player, 0)
		until("confirm")
		lab.camera_rig.set_process(false)
		lab.camera.position = bow.position + Vector2(35, -24)
		lab.camera.zoom = Vector2(3, 3)
		lab.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/inari_bow_attack_confirm.png"
		)
	sequence.begin(lab.player, 0)
	bow._die(null)
	for frame in 120:
		tick()
	assert(not sequence.active() and shots.size() == 2)
	lab.queue_free()
	await process_frame
	print("BOW_ATTACK_PASS shots=", shots.size())
	quit()
