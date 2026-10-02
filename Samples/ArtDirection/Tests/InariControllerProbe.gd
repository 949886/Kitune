extends SceneTree
## Compare actual controller motion with independently calculated source values.
## This does not equate Godot contact resolution with Unity's custom ray solver.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
var player: CharacterBody2D
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)


func _wait_frames(count: int) -> void:
	for frame in count:
		await physics_frame


func _reset() -> void:
	for name in ["left", "right", "up", "down", "jump", "dash", "attack", "throw", "teleport"]:
		Input.action_release(player.input_action(name))
	player.respawn()
	await _wait_frames(180)


func _tap(name: String) -> void:
	Input.action_press(player.input_action(name))
	await _wait_frames(2)
	Input.action_release(player.input_action(name))


func run() -> void:
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(10000, 30)
	floor_shape.shape = box
	floor_shape.position.y = 15
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	player = Player.new()
	# Reuse the source-motion oracle for optional visual skins as well: a skin
	# must never alter jumps, attacks, wall contacts or teleport distances.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("appearance="):
			player.appearance_path = argument.trim_prefix("appearance=")
	root.add_child(player)
	player.checkpoint = Vector2.ZERO
	await _reset()

	# 21 Unity units/sec * 16 pixels/unit, including the source's instant stop.
	Input.action_press(player.input_action("right"))
	await _wait_frames(4)
	_expect(is_equal_approx(player.velocity.x, 336.0), "Source run speed must be 336 px/s")
	Input.action_release(player.input_action("right"))
	await _wait_frames(2)
	_expect(is_zero_approx(player.velocity.x), "Source release curve must stop immediately")

	# Continuous held apex is 70.857 px; 60 Hz integration lands slightly below it.
	await _reset()
	Input.action_press(player.input_action("jump"))
	var held_apex := 0.0
	for frame in 80:
		await physics_frame
		held_apex = maxf(held_apex, -player.position.y)
	Input.action_release(player.input_action("jump"))
	_expect(held_apex > 64.0 and held_apex < 73.0, "Held jump apex differs from source equations")

	await _reset()
	await _tap("jump")
	var short_apex := 0.0
	for frame in 80:
		await physics_frame
		short_apex = maxf(short_apex, -player.position.y)
	_expect(short_apex < held_apex * 0.6, "Releasing jump must truncate its height")

	await _reset()
	await _tap("jump")
	await _wait_frames(4)
	await _tap("jump")
	_expect(not player.can_air_jump, "Second jump must consume the air jump")
	_expect(player.sprite.clip_name == "double_jump", "Second jump must use original animation")

	await _reset()
	var start: Vector2 = player.position
	await _tap("dash")
	await _wait_frames(24)
	_expect(
		absf(player.position.x - start.x - 176.0) < 1.0, "Dash must travel source distance 176 px"
	)
	_expect(player.dash_ready_at > player.clock, "Source dash cooldown must remain active")

	await _reset()
	await _tap("attack")
	await _wait_frames(8)
	await _tap("attack")
	await _wait_frames(10)
	await _tap("attack")
	await _wait_frames(10)
	_expect(player.attack_index == 2, "Buffered attacks must reach the third source combo")

	await _reset()
	var wall := StaticBody2D.new()
	wall.collision_layer = 1 | 16
	var wall_shape := CollisionShape2D.new()
	var wall_box := RectangleShape2D.new()
	wall_box.size = Vector2(20, 160)
	wall_shape.shape = wall_box
	wall.position = Vector2(300, -80)
	wall.add_child(wall_shape)
	root.add_child(wall)
	await _wait_frames(2)
	player.throw_projectile(Vector2.RIGHT)
	await _wait_frames(8)
	_expect(player.projectile_active, "Original projectile must fly before reaching max range")
	_expect(not player.try_teleport(), "Source teleport must wait for impact")
	await _wait_frames(8)
	_expect(player.projectile_stuck, "Projectile must attach to the test wall")
	var projectile_target: Vector2 = player.projectile.global_position
	var stamina_before: float = player.stamina
	print(
		"TELEPORT_FIXTURE player=",
		player.position,
		" target=",
		projectile_target,
		" body=",
		player.body_size,
		" stamina=",
		stamina_before
	)
	var expected_center: Vector2 = (
		projectile_target
		+ Vector2.UP * player.safe_margin  # Native overlap search starts one skin upward.
		+ player.projectile_normal * (player.body_size.x * 0.5 + player.safe_margin)
	)
	_expect(player.try_teleport(), "Teleport to a stuck projectile must succeed")
	_expect(
		player.position.distance_to(expected_center - player.body_shape.position) < 0.1,
		"Teleport must align the collider center"
	)
	_expect(
		is_equal_approx(stamina_before - player.stamina, 8.0),
		"Teleport must cost original stamina amount"
	)
	_expect(player.can_air_jump, "Teleport must restore air jump")
	for info: Dictionary in player.tuning.attacks.AttackInfo.AttackInfos:
		_expect(
			info.has("AttackMovementInfo"), "Teleport/reset must not clear source attack tuning"
		)

	for clip_name: String in player.sprite.clips:
		var clip: Dictionary = player.sprite.clips[clip_name]
		_expect(not clip.frames.is_empty(), "Empty original animation: " + clip_name)
		player.sprite.play(clip_name)
		_expect(player.sprite.texture != null, "Missing animation texture: " + clip_name)

	for group: String in player.audio.groups:
		for filename: String in player.audio.groups[group]:
			var sound := load(player.audio.AUDIO_ROOT + filename) as AudioStream
			_expect(sound != null and sound.get_length() > 0.0, "Invalid source audio: " + filename)

	print(
		"INARI_CONTROLLER apex_held=",
		held_apex,
		" apex_short=",
		short_apex,
		" clips=",
		player.sprite.clips.size()
	)
	print(
		(
			"INARI_CONTROLLER_PASS"
			if failures.is_empty()
			else "INARI_CONTROLLER_FAILED " + str(failures)
		)
	)
	quit(0 if failures.is_empty() else 1)
