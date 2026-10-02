extends SceneTree
## Native controller DLL results, actual left-stick/D-pad events and displacement.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MovementInput = preload("res://Samples/ArtDirection/Runtime/InariMovementInput.gd")


func _initialize() -> void:
	call_deferred("run")


func axes(value: Vector2) -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = value.x if axis == JOY_AXIS_LEFT_X else value.y
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var oracle: Dictionary = Assets.read_json(Assets.ROOT + "stick_oracle.json")
	var profile: Dictionary = Assets.read_json(Assets.ROOT + "input_processing.json")
	assert(oracle.profile_sha256 == FileAccess.get_sha256(Assets.ROOT + "input_processing.json"))
	assert(oracle.movement_assembly_sha256 == profile.source_sha256["Managed/Assembly-CSharp.dll"])
	var movement := MovementInput.new()
	movement.configure()
	assert(oracle.movement_samples.size() == 487)
	for sample: Dictionary in oracle.movement_samples:
		var raw := Assets.vec(sample.input) * Vector2(1, -1)
		var expected := Assets.vec(sample.output) * Vector2(1, -1)
		var actual := movement.process_stick(movement.processor.process(raw))
		assert(actual == expected, "Native movement mismatch at " + str(raw))
	print("MOVEMENT_NATIVE_DLL samples=", oracle.movement_samples.size(), " exact=true")
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
	axes(Vector2(0.15, 0))
	assert(player._axis("left", "right") == 0.0)
	axes(Vector2(0.2, 0))
	assert(player._axis("left", "right") == 1.0)
	var start: Vector2 = player.position
	player._physics_process(1.0 / 60.0)
	var expected_distance: float = float(player.physics.moveSpeed) * player.units / 60.0
	assert(absf(player.position.x - start.x - expected_distance) < 0.003)
	axes(Vector2(0.0, 0.5))
	assert(player._axis("left", "right") == 1.0, "Native Mathf.Sign(0) is positive")
	assert(player._axis("up", "down") == 0.0)
	axes(Vector2(0.0, 0.74))
	assert(player._axis("left", "right") == 0.0, "Sit clears lateral input in midair too")
	assert(player._axis("up", "down") == 1.0)
	axes(Vector2(0.0, -0.74))
	assert(player._axis("left", "right") == 1.0)
	assert(player._axis("up", "down") == -1.0)
	axes(Vector2(0.5, -0.5))
	assert(player._axis("up", "down") == 0.0, "Diagonal is below the vertical gate")
	button(JOY_BUTTON_DPAD_LEFT, true)
	assert(player._axis("left", "right") == -1.0)
	axes(Vector2(0.6, -0.5))
	assert(player._axis("left", "right") == 1.0, "Latest stick callback takes precedence")
	axes(Vector2.ZERO)
	assert(player._axis("left", "right") == 0.0, "Cancel does not poll a held D-pad again")
	button(JOY_BUTTON_DPAD_LEFT, false)
	button(JOY_BUTTON_DPAD_LEFT, true)
	assert(player._axis("left", "right") == -1.0)
	axes(Vector2(0.01, 0.01))
	assert(player._axis("left", "right") == -1.0, "Deadzone noise is not a callback")
	button(JOY_BUTTON_DPAD_LEFT, false)
	lab.queue_free()
	await process_frame
	print("MOVEMENT_INPUT_PASS")
	quit()
