extends SceneTree
## Real kunai/Q entry, deferred cancellation and the native two-clip recovery turn.

var lab: Node
var bow: Node
var combat: RefCounted
var sequence: RefCounted
var shots: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func tick() -> void:
	combat.step(1.0 / 60.0)
	bow.motion_animation.advance(1.0 / 60.0)
	bow._sync_visuals()


func until(state: String) -> void:
	for frame in 300:
		if sequence.state == state:
			return
		tick()
	assert(false, "Expected recovery state " + state)


func until_entry(phase: String) -> void:
	for frame in 60:
		if sequence.entry_phase == phase:
			return
		tick()
	assert(false, "Expected attack entry phase " + phase)


func place_player(offset: Vector2) -> void:
	lab.player.position = sequence.center() + offset - lab.player.body_shape.position
	await frames(2)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	await frames(20)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	combat = bow.bow_combat
	sequence = bow.bow_attack
	combat.target = lab.player
	bow.motion_animation.set_process(false)
	lab.player.position = bow.position + Vector2(-48, 32)
	lab.player.velocity = Vector2.ZERO
	await frames(3)
	sequence.begin(lab.player, 1)
	var aim := InputEventMouseMotion.new()
	aim.position = lab.viewport.get_canvas_transform() * sequence.center()
	lab.viewport.push_input(aim, true)
	Input.action_press(lab.player.input_action("throw"))
	await frames(2)
	Input.action_release(lab.player.input_action("throw"))
	await frames(10)
	assert(lab.player.projectile_stuck and lab.player.projectile_target == bow)
	assert(sequence.state == "ready" and not combat.cancel_pending)
	assert(bow.health == 280.0 and not sequence.targeting_attack)
	Input.action_press(lab.player.input_action("teleport"))
	await frames(2)
	Input.action_release(lab.player.input_action("teleport"))
	assert(bow.health == 230.0 and bow.kunai.weak_points == 1)
	assert(combat.cancel_pending and sequence.targeting_attack)
	assert(sequence.state == "ready", "Weak points queue the state change until the next update")
	lab.player.set_physics_process(false)
	tick()
	assert(sequence.state == "cancel" and bow.motion == "AttackCancel:1")
	assert(sequence.attack_index == 1)
	for frame in 5:
		tick()
	var elapsed := float(sequence.elapsed)
	bow.kunai.dash(lab.player)
	assert(not combat.cancel_pending and sequence.elapsed == elapsed)
	until("idle")
	assert(sequence.attack_index == 1 and sequence.targeting_attack)
	await place_player(Vector2(32, 0))
	combat._enter_ready()
	assert(sequence.attack_index == 0, "Retained melee index suppresses the next close decision")
	sequence.reset()

	# The next attack locks aim, then the player moves behind it. The source
	# turns through two clips but keeps the arrow origin/angle captured before them.
	await place_player(Vector2(220, 0))
	sequence.begin(lab.player, 0)
	until("confirm")
	await place_player(Vector2(-220, 0))
	sequence.arrow_launched.connect(
		func(arrow: Node2D):
			shots.append({"position": arrow.global_position, "angle": arrow.rotation})
			arrow.queue_free()
	)
	until("attack")
	assert(sequence.entry_phase == "flip_start" and bow.motion == "FlipStart:0")
	assert(bow.facing == 1.0 and shots.is_empty())
	assert(is_equal_approx(bow.motion_duration, 1.0 / 6.0))
	var captured_origin: Vector2 = sequence.shot_origin
	var captured_angle := float(sequence.shot_angle)
	await place_player(Vector2(220, 0))
	for frame in 9:
		tick()
	assert(sequence.entry_phase == "flip_start" and bow.facing == 1.0)
	until_entry("flip_end")
	assert(bow.facing == -1.0 and bow.motion == "FlipEnd:0" and shots.is_empty())
	if DisplayServer.get_name() != "headless":
		# A close inspection fixture; the playable scene retains its original rig.
		lab.camera_rig.set_process(false)
		lab.camera.position = bow.position + Vector2(0, -20)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bow_recovery.png")
	until_entry("")
	assert(shots.size() == 1 and not sequence.targeting_attack)
	assert(shots[0].position.distance_to(captured_origin) < 0.001)
	assert(is_equal_approx(shots[0].angle, captured_angle))
	assert(bow.motion == "Attack:0" and sequence.elapsed == 0.0)
	combat.retargetable = false
	bow.kunai.dash(lab.player)
	tick()
	assert(sequence.state == "cancel" and combat.retargetable)
	assert(bow.combat_animation_index == 0 and shots.size() == 1)
	until("idle")

	# Whichever deferred request arrives first wins; marking the targeted
	# attack still happens if an earlier group request owns the transition.
	bow.health = float(bow.data.profile.f_maximumHealth)
	sequence.begin(lab.player, 1)
	combat.request_retarget()
	bow.kunai.dash(lab.player)
	assert(combat.retarget_pending and not combat.cancel_pending)
	assert(sequence.targeting_attack)
	tick()
	assert(combat.state == "retarget")
	combat.reset()
	bow.motion_animation.set_process(false)
	sequence.begin(lab.player, 1)
	bow.kunai.dash(lab.player)
	combat.request_retarget()
	assert(combat.cancel_pending and not combat.retarget_pending)
	tick()
	assert(sequence.state == "cancel")
	until("idle")
	# Same-side recovery consumes the marker without inserting turn clips.
	sequence.begin(lab.player, 1)
	until("attack")
	assert(sequence.entry_phase.is_empty() and not sequence.targeting_attack)
	assert(bow.motion == "Attack:1")
	until("idle")

	# Post exit resets both the stored attack index and retreat opportunity,
	# including when weak-point cancellation interrupts recovery.
	sequence.begin(lab.player, 1)
	until("post")
	combat.can_run_away = false
	bow.kunai.dash(lab.player)
	tick()
	assert(sequence.state == "cancel" and sequence.attack_index == 0)
	assert(combat.can_run_away)
	until("idle")
	sequence.begin(lab.player, 0)
	bow.data = bow.data.duplicate(true)
	bow.data.kunai.ignore_weak_point = true
	bow.kunai.dash(lab.player)
	assert(not combat.cancel_pending and sequence.state == "ready")
	bow.data.kunai.ignore_weak_point = false
	bow.health = 49.0
	bow.kunai.dash(lab.player)
	assert(bow.dead and not combat.cancel_pending and not sequence.active())
	for frame in 30:
		tick()
	assert(shots.size() == 1)
	lab.queue_free()
	await process_frame
	print("BOW_RECOVERY_PASS")
	quit()
