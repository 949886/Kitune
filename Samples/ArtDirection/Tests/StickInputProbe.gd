extends SceneTree
## Original-DLL oracle plus actual routed input, jitter, cancellation and air aim.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Processor = preload("res://Samples/ArtDirection/Runtime/InariStickProcessor.gd")


func _initialize() -> void:
	call_deferred("run")


func axes(value: Vector2, device := 0) -> void:
	for axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		var event := InputEventJoypadMotion.new()
		event.device = device
		event.axis = axis
		event.axis_value = value.x if axis == JOY_AXIS_RIGHT_X else value.y
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var profile: Dictionary = Assets.read_json(Assets.ROOT + "input_processing.json")
	var oracle: Dictionary = Assets.read_json(Assets.ROOT + "stick_oracle.json")
	assert(oracle.profile_sha256 == FileAccess.get_sha256(Assets.ROOT + "input_processing.json"))
	assert(
		(
			oracle.source_sha256["Unity.InputSystem.dll"]
			== profile.source_sha256["Managed/Unity.InputSystem.dll"]
		)
	)
	assert(profile.settings.preloaded and is_equal_approx(profile.right_stick.minimum, 0.1))
	var processor := Processor.new()
	processor.configure(profile.right_stick)
	var largest := 0.0
	for sample: Dictionary in oracle.samples:
		var actual := processor.process(Assets.vec(sample.input))
		var expected := Assets.vec(sample.output)
		largest = maxf(largest, actual.distance_to(expected))
	assert(oracle.samples.size() == 481 and largest < 0.0000002)
	print("STICK_NATIVE_DLL samples=", oracle.samples.size(), " max_error=", largest)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
	player.position = Vector2(-20000, -20000)
	player.action_state = ""
	player.velocity = Vector2.ZERO
	await physics_frame
	player.move_and_slide()
	var targeting: RefCounted = player.targeting
	player.clock = 10.0
	var previous_deadline: float = targeting.aim_until
	for value in [Vector2(0.03, 0.04), Vector2(0.05, 0.02), Vector2.ZERO]:
		axes(value)
		assert(targeting.stick == Vector2.ZERO and targeting.aim_until == previous_deadline)
	axes(Vector2(0.08, 0.08))
	assert(targeting.stick.length() > 0.0, "Deadzone is radial, not independent per axis")
	assert(not targeting.right_stick_pressed())
	assert(targeting.aim_until > player.clock)
	axes(Vector2(0.15, 0.0))
	player.aim_time.update()
	assert(targeting.stick.x > 0.0 and targeting.stick.x < targeting.right_stick_threshold)
	assert(player.source_time_scale == 1.0, "Raw 0.15 must not enter air-aim slow motion")
	axes(Vector2(0.19, 0.0))
	assert(not targeting.right_stick_pressed())
	axes(Vector2(0.2, 0.0))
	player.aim_time.update()
	assert(targeting.right_stick_pressed())
	assert(is_equal_approx(player.source_time_scale, player.aim_time.settings.air_scale))
	previous_deadline = targeting.aim_until
	player.clock += 1.0
	axes(Vector2(0.2, 0.0))
	assert(targeting.aim_until == previous_deadline, "An unchanged control does not perform again")
	axes(Vector2.ZERO)
	assert(targeting.stick == Vector2.ZERO and targeting.aim_until > previous_deadline)
	previous_deadline = targeting.aim_until
	player.clock += 1.0
	axes(Vector2(0.01, 0.01))
	assert(
		targeting.aim_until == previous_deadline, "Canceled actions remain waiting through noise"
	)
	player.aim_time.update()
	assert(player.source_time_scale == 1.0)
	axes(Vector2(1.0, 1.0))
	assert(is_equal_approx(targeting.stick.length(), 1.0))
	assert(targeting.stick.is_equal_approx(Vector2.ONE.normalized()))
	axes(Vector2(0.5, 0.0), 1)
	assert(targeting.gamepad_device == 1 and targeting.stick.y == 0.0)
	assert(targeting.raw_stick == Vector2(0.5, 0.0))
	lab.queue_free()
	await process_frame
	print("STICK_INPUT_PASS")
	quit()
