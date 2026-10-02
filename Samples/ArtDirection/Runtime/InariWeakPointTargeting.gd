extends RefCounted
## PlayerStateMachine's range-gated mouse selection and gamepad enemy snap.

signal changed(target: Node)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Marker = preload("res://Samples/ArtDirection/Runtime/InariTargetMarker.gd")
const StickProcessor = preload("res://Samples/ArtDirection/Runtime/InariStickProcessor.gd")
const GamepadAim = preload("res://Samples/ArtDirection/Runtime/InariGamepadAim.gd")

var actor: CharacterBody2D
var enemies: Array = []
var settings: Dictionary
var current: Node
var snap_target: Node
var using_gamepad := false
var gamepad_device := -1
var stick := Vector2.ZERO
var raw_stick := Vector2.ZERO
var stick_processor := StickProcessor.new()
var right_stick_threshold := 0.0
var pad_direction := Vector2.RIGHT
var aim_until := 0.0
var buffer_until := 0.0
var presentation: Node
var gamepad_aim: Node2D


func configure(owner_node: CharacterBody2D) -> void:
	actor = owner_node
	settings = Assets.read_json(Assets.ROOT + "targeting.json")
	stick_processor.configure(Assets.read_json(Assets.ROOT + "input_processing.json").right_stick)
	# Unity compares Vector2.magnitude to a C# float literal, not a JSON double.
	right_stick_threshold = PackedFloat32Array([settings.right_stick_deadzone])[0]


func configure_presentation(stage: Node) -> void:
	presentation = Marker.new()
	actor.add_child(presentation)
	presentation.configure(actor, stage)
	gamepad_aim = GamepadAim.new()
	actor.add_child(gamepad_aim)
	gamepad_aim.configure(actor, stage)


func input_event(event: InputEvent) -> void:
	# Native device tracking ignores mouse position/delta; moving the mouse alone
	# does not steal a live gamepad selection.
	if event is InputEventKey or event is InputEventMouseButton:
		if event.pressed:
			using_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if (
			(event is InputEventJoypadButton and event.pressed)
			or (event is InputEventJoypadMotion and not is_zero_approx(event.axis_value))
		):
			using_gamepad = true
		if gamepad_device != event.device:
			gamepad_device = event.device
			stick = Vector2.ZERO
			raw_stick = Vector2.ZERO
		if event is InputEventJoypadMotion:
			var previous_raw := raw_stick
			if event.axis == JOY_AXIS_RIGHT_X:
				raw_stick.x = event.axis_value
			elif event.axis == JOY_AXIS_RIGHT_Y:
				raw_stick.y = event.axis_value
			else:
				return
			if raw_stick == previous_raw:
				return
			var processed: Vector2 = stick_processor.process(raw_stick)
			if processed == Vector2.ZERO and stick == Vector2.ZERO:
				# Waiting Value actions ignore unactuated noise. Active actions
				# still perform on raw changes, even when normalization matches.
				return
			stick = processed
			aim_until = actor.clock + float(actor.combat.gamePadAimRenderTime)


func step(mouse_position: Vector2) -> void:
	if is_instance_valid(presentation):
		presentation.update_line(current if is_instance_valid(current) else null)
	var has_ranges := _select(mouse_position)
	if is_instance_valid(presentation):
		presentation.update_selection(current, has_ranges, using_gamepad)
	if is_instance_valid(gamepad_aim):
		gamepad_aim.update_aim(self)


func _select(mouse_position: Vector2) -> bool:
	if using_gamepad:
		_update_snap()
	else:
		snap_target = null
	var ranges: Array = []
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.weakpoint_presentation._contact():
			ranges.append(enemy)
			if ranges.size() == int(settings.query_capacity):
				break
	if ranges.is_empty():
		_set_current(null)
		return false
	if using_gamepad:
		var candidate: Node = null
		if is_instance_valid(snap_target) and snap_target in ranges and _clear_sight(snap_target):
			candidate = snap_target
		_set_current(candidate)
		return true
	for enemy: Node in _circle(mouse_position, float(actor.combat.WeakPointSize)):
		if enemy in ranges and _clear_sight(enemy):
			buffer_until = (
				actor.clock
				+ float(actor.combat.DashTargetBufferFrame) * float(actor.tuning.fixed_timestep)
			)
			_set_current(enemy)
			return true
	# Equality keeps the old target. Native uses a strict deadline comparison.
	if buffer_until < actor.clock or not is_instance_valid(current):
		_set_current(null)
	return true


func _update_snap() -> void:
	var pressed := right_stick_pressed()
	var direction := stick
	if pressed or not is_instance_valid(snap_target):
		if not pressed:
			direction = Vector2(actor.facing, 0.0)
			pad_direction = direction
		if aim_until > actor.clock:
			snap_target = _acquire(direction)
			if is_instance_valid(snap_target):
				_check_snap(direction)
			else:
				# Ground/platform aim assistance has a separate native solver.
				pad_direction = direction.normalized()
	elif is_instance_valid(snap_target):
		_check_snap(direction)


func _acquire(direction: Vector2) -> Node:
	var result: Node = null
	var nearest: float = float(actor.combat.gamePadSnapAssistRadius) * actor.units
	var minimum_dot := cos(deg_to_rad(float(actor.combat.gamePadSnapAcquireAngle)))
	var aim := direction.normalized() if direction != Vector2.ZERO else Vector2(actor.facing, 0.0)
	for enemy: Node in _circle(_center(), float(actor.combat.gamePadSnapAssistRadius)):
		var offset: Vector2 = enemy.global_position - _center()
		var distance := offset.length()
		if aim.dot(offset.normalized()) < minimum_dot or distance > nearest:
			continue
		if _clear_sight(enemy):
			nearest = distance
			result = enemy
	return result


func _check_snap(direction: Vector2) -> void:
	var offset: Vector2 = snap_target.global_position - _center()
	# Unity Vector2.Angle returns zero when either vector has zero length.
	var angle := 0.0 if direction == Vector2.ZERO else absf(rad_to_deg(offset.angle_to(direction)))
	if (
		snap_target.dead
		or not _clear_sight(snap_target)
		or offset.length() > float(actor.combat.gamePadSnapReleaseDistance) * actor.units
		or angle > float(actor.combat.gamePadSnapReleaseAngle)
	):
		snap_target = null
		aim_until = actor.clock + float(actor.combat.gamePadAimRenderTime)
	else:
		pad_direction = offset.normalized()


func right_stick_pressed() -> bool:
	return stick.length() > right_stick_threshold


func throw_direction() -> Vector2:
	return pad_direction


func _circle(position: Vector2, radius: float) -> Array:
	var shape := CircleShape2D.new()
	shape.radius = radius * actor.units
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = Collision.ENEMY_TARGET
	var result: Array = []
	for hit: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(
		query, int(settings.query_capacity)
	):
		if hit.collider in enemies and hit.collider not in result:
			result.append(hit.collider)
	return result


func _clear_sight(enemy: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		_center(), enemy.global_position, Collision.SIGHT_SURFACE
	)
	return actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _center() -> Vector2:
	return actor.global_position + actor.body_shape.position


func _set_current(target: Node) -> void:
	var had_current := current != null
	var previous_id := current.get_instance_id() if is_instance_valid(current) else 0
	if previous_id != 0 and current != target:
		current.weakpoint_presentation.outline.set_selected(false)
	current = target
	if is_instance_valid(current):
		current.weakpoint_presentation.outline.set_selected(true)
	var current_id := current.get_instance_id() if is_instance_valid(current) else 0
	if previous_id != current_id or (had_current and previous_id == 0):
		changed.emit(current)


func reset() -> void:
	_set_current(null)
	if is_instance_valid(presentation):
		presentation.reset()
	if is_instance_valid(gamepad_aim):
		gamepad_aim.hide()
	snap_target = null
	aim_until = 0.0
	buffer_until = 0.0
