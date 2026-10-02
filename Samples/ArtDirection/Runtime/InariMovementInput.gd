extends RefCounted
## Preserve left-stick callbacks before converting Unity's upward Y to Godot Y.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Processor = preload("res://Samples/ArtDirection/Runtime/InariStickProcessor.gd")
const Controls = preload("res://Samples/ArtDirection/Runtime/InariInput.gd")

var processor := Processor.new()
var activation_threshold := 0.0
var vertical_threshold := 0.0
var raw_stick := Vector2.ZERO
var stick := Vector2.ZERO
var direction := Vector2.ZERO
var digital := Vector2.ZERO
var device := -1


func configure() -> void:
	var source: Dictionary = Assets.read_json(Assets.ROOT + "input_processing.json").left_stick
	processor.configure(source)
	activation_threshold = PackedFloat32Array([source.activation_threshold])[0]
	vertical_threshold = PackedFloat32Array([source.vertical_threshold])[0]


func process_stick(value: Vector2) -> Vector2:
	var result := Vector2.ZERO
	if value.length() > activation_threshold:
		# Unity Mathf.Sign(0) returns +1, including a perfectly vertical push.
		result.x = 1.0 if value.x >= 0.0 else -1.0
		if absf(value.y) > vertical_threshold:
			result.y = 1.0 if value.y >= 0.0 else -1.0
	if result.y > 0.0:
		# Native Sit clears InputX, even in midair. Godot positive Y is down.
		result.x = 0.0
	return result


func input_event(event: InputEvent) -> void:
	_sync_digital()
	if not event is InputEventJoypadMotion:
		return
	if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		return
	if device != event.device:
		device = event.device
		raw_stick = Vector2.ZERO
		stick = Vector2.ZERO
	var previous := raw_stick
	if event.axis == JOY_AXIS_LEFT_X:
		raw_stick.x = event.axis_value
	else:
		raw_stick.y = event.axis_value
	if raw_stick == previous:
		return
	var processed := processor.process(raw_stick)
	if processed == Vector2.ZERO and stick == Vector2.ZERO:
		return
	stick = processed
	direction = process_stick(stick)


func read_direction() -> Vector2:
	_sync_digital()
	return direction


func _sync_digital() -> void:
	# Only changed digital axes invoke the corresponding source callbacks.
	# Keep a stick cancellation from silently reviving a still-held D-pad key.
	var current := Vector2(
		Input.get_axis(Controls.action("left"), Controls.action("right")),
		Input.get_axis(Controls.action("up"), Controls.action("down"))
	)
	if current.x != digital.x:
		direction.x = signf(current.x)
	if current.y != digital.y:
		direction.y = signf(current.y)
	digital = current
