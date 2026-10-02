extends RefCounted
## Unity Input System's radial StickDeadzoneProcessor, before action callbacks.

var minimum := 0.0
var maximum := 1.0


func configure(source: Dictionary) -> void:
	assert(source.processor == "stickDeadzone" and source.action.type == "Value")
	minimum = source.minimum
	maximum = source.maximum
	assert(minimum >= 0.0 and maximum > minimum)


func process(value: Vector2) -> Vector2:
	# Keep the source's float arithmetic at the activation boundary. Vector2
	# stores floats too, but GDScript scalar subtraction/division uses doubles.
	var squared := _single(_single(value.x * value.x) + _single(value.y * value.y))
	var magnitude := _single(sqrt(squared))
	if magnitude < minimum:
		return Vector2.ZERO
	var adjusted := 1.0
	if magnitude <= maximum:
		adjusted = _single(_single(magnitude - minimum) / _single(maximum - minimum))
	if adjusted == 0.0:
		return Vector2.ZERO
	return value * _single(adjusted / magnitude)


func _single(value: float) -> float:
	return PackedFloat32Array([value])[0]
