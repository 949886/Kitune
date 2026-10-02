extends RefCounted
## Four authored UV strips, with the source shortest-wrap OutQuad tween.
## Material instances belong to one terminal and never modify cached resources.
var digits: Array[Dictionary] = []


func configure(records: Array, visuals: Dictionary) -> void:
	for index in records.size():
		var digit: Dictionary = records[index]
		var visual: Node = visuals[digit.go]
		visual.material = visual.material.duplicate()
		visual.material.set_shader_parameter("source_uv_controls", true)
		visual.material.set_shader_parameter(
			"source_uv_clip",
			Vector4(
				digit.floats._ClipUvLeft,
				digit.floats._ClipUvRight,
				digit.floats._ClipUvDown,
				digit.floats._ClipUvUp
			)
		)
		digits.append(
			{"visual": visual, "index": index, "value": 0.0, "from": 0.0, "to": 0.0, "time": 1.0}
		)


func update(seconds: float, immediate: bool) -> void:
	var minute := int(seconds / 60.0)
	var second := int(fmod(seconds, 60.0))
	var offsets := [
		(9 - (minute / 10) % 10) * 0.1,
		(9 - minute % 10) * 0.1,
		(5 - (second / 10) % 6) / 6.0,
		(9 - second % 10) * 0.1
	]
	for digit: Dictionary in digits:
		var desired: float = offsets[int(digit.index)]
		if immediate:
			digit.value = desired
			digit.time = 1.0
		else:
			var difference := desired - float(digit.value)
			# Source Mathf.Round ties to even; these authored steps never tie.
			desired = float(digit.value) + difference - roundf(difference)
			digit.time = 0.0
		digit.from = digit.value
		digit.to = desired
	step(0.0)


func step(delta: float) -> void:
	for digit: Dictionary in digits:
		digit.time = minf(float(digit.time) + delta, 1.0)
		var t := 1.0 - (1.0 - float(digit.time)) * (1.0 - float(digit.time))
		digit.value = lerpf(float(digit.from), float(digit.to), t)
		digit.visual.material.set_shader_parameter("source_uv_offset", Vector2(0.0, digit.value))
