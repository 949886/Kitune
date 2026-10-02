extends SceneTree
## Actual source-mode HP, hit cancellation, immunity, blink and death lifecycle.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Rig = preload("res://Samples/ArtDirection/Runtime/InariCameraRig.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var shakes: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	viewport.world_2d = World2D.new()
	root.add_child(viewport)
	var player := Player.new()
	viewport.add_child(player)
	player.set_physics_process(false)
	player.camera_shake_requested.connect(func(kind: String): shakes.append(kind))
	var rig := Rig.new()
	viewport.add_child(rig)
	rig.configure_2d({}, player, Assets.read_json(Assets.ROOT + "camera.json"))
	rig.set_process(false)
	var source := player.damage.settings
	assert(source.normal_hp == 1 and source.story_hp == 3)
	assert(source.blink_duration == 2.0 and source.blink_interval == 0.1)
	assert(player.damage.health == 1 and player.damage.maximum == 1)

	# Normal mode dies from one hit. Death waits for the shipped animation, then
	# restores collision, HP, opacity and spawn at the existing checkpoint.
	player.checkpoint = Vector2(100, 200)
	assert(player.receive_damage(1.0))
	assert(player.dead and player.damage.health == 0 and not player.damage.blinking)
	assert(player.sprite.clip_name == "dead" and shakes == ["Damaged"])
	assert(player.audio.last_selection.has("hit"))
	assert(not player.receive_damage(1.0))
	await process_frame
	assert(player.body_shape.disabled)
	var duration := (
		float(player.sprite.clips.dead.length) / float(player.sprite.clips.dead.get("speed", 1.0))
	)
	player._physics_process(duration * 0.5)
	assert(player.dead)
	player._physics_process(duration * 0.5 + 0.001)
	await process_frame
	assert(not player.dead and not player.body_shape.disabled)
	assert(player.position == player.checkpoint and player.damage.health == 1)
	assert(player.sprite.clip_name == "spawn" and player.action_state == "spawn")

	# Story mode loses exactly one of three HP. Late Hit/Idle cancels queued
	# attacks; the two native Damaged requests replace, rather than stack, impulses.
	player.story_mode = true
	player.respawn()
	player.action_state = ""
	player._start_attack(0)
	player.attack_buffer_until = player.clock + 10.0
	shakes.clear()
	assert(player.receive_damage(1.0))
	assert(player.damage.health == 2 and player.damage.blinking and not player.dead)
	assert(player.attack_info.is_empty() and player.action_state.is_empty())
	assert(player.attack_buffer_until == 0.0 and player.sprite.clip_name == "idle")
	assert(shakes == ["Damaged", "Damaged"])
	assert(not rig.impulse.active.is_empty())
	assert(is_equal_approx(player.sprite.modulate.a, 0.1))
	assert(not player.receive_damage(1.0) and player.damage.health == 2)

	# Movement and jump inputs remain live while blinking. Isolate this from
	# the previous attack curve so the observed motion is ordinary locomotion.
	player.path_time = player.path_duration
	var before := player.position
	Input.action_press(player.input_action("right"))
	player._physics_process(1.0 / 60.0)
	Input.action_release(player.input_action("right"))
	assert(player.position.x > before.x and player.damage.blinking)
	player.damage.blink_elapsed = 0.0
	for step in range(1, 20):
		player.damage.advance(0.1)
		assert(player.damage.blinking)
		var alpha := 1.0 if step % 2 == 1 else 0.1
		assert(is_equal_approx(player.sprite.modulate.a, alpha))
	player.damage.advance(0.099)
	assert(player.damage.blinking and not player.receive_damage(1.0))
	player.damage.advance(0.001)
	assert(not player.damage.blinking and player.sprite.modulate.a == 1.0)
	assert(player.receive_damage(1.0) and player.damage.health == 1)

	# Frame subdivision must not extend a two-second blink. Reset clears a
	# partly faded sprite even when the user retries during invulnerability.
	for steps in [30, 60, 144]:
		player.respawn()
		player.action_state = ""
		assert(player.receive_damage(1.0))
		for step in steps:
			player.damage.advance(2.0 / steps)
		assert(not player.damage.blinking and player.sprite.modulate.a == 1.0)
	player.receive_damage(1.0)
	player.respawn()
	assert(not player.damage.blinking and player.damage.health == 3)
	assert(player.sprite.modulate.a == 1.0)

	# State immunity includes dash/teleport recovery, not merely displacement.
	for state in ["dash", "teleport", "weakpoint_execution", "hit"]:
		player.action_state = state
		assert(not player.receive_damage(999.0))
		assert(player.damage.health == 3 and not player.dead)
	player.action_state = ""
	assert(not player.receive_damage(-1.0))

	# Use a real imported source knockback curve, but a known direction. It
	# changes movement without charging runtime HP, as PlayerStateMachine does.
	var knockback: Dictionary = (
		player.tuning.attacks.AttackInfo.AttackInfos[0].AttackKnockBackInfo.duplicate(true)
	)
	knockback.DirectionX = -1.0
	player.facing = 1.0
	shakes.clear()
	before = player.position
	assert(player.receive_damage(0.0, knockback))
	assert(player.damage.health == 3 and shakes == ["Damaged"])
	assert(is_equal_approx(player.path_target.x - before.x, -float(knockback.Power) * player.units))
	assert(player.path_duration == float(knockback.Duration))
	var expected_x := before.x
	var elapsed := 0.0
	while player.path_time < player.path_duration:
		await physics_frame
		elapsed = float(
			PackedFloat32Array([elapsed + float(PackedFloat32Array([1.0 / 60.0])[0])])[0]
		)
		if elapsed < float(knockback.Duration):
			# The shipped two-key curve is 2t-t^2. Hit attenuates velocity by
			# 1-curve(t), rather than interpolating all the way to the target.
			var ratio := elapsed / float(knockback.Duration)
			expected_x -= (
				float(knockback.Power)
				* player.units
				/ float(knockback.Duration)
				* pow(1.0 - ratio, 2)
				/ 60.0
			)
		player._follow_motion_curve(1.0 / 60.0, 0.0)
	assert(absf(player.position.x - expected_x) < 0.01)
	viewport.queue_free()
	await process_frame
	print("PLAYER_DAMAGE_PASS")
	quit()
