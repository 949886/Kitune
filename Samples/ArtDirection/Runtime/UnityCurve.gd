extends RefCounted
## Evaluate the unweighted Hermite keys exported from Unity's AnimationCurve.


static func evaluate(curve: Dictionary, time: float) -> float:
	var keys: Array = curve.m_Curve
	if keys.is_empty():
		return time
	if time <= float(keys[0].time):
		return float(keys[0].value)

	for index in range(1, keys.size()):
		var right: Dictionary = keys[index]
		if time > float(right.time):
			continue

		var left: Dictionary = keys[index - 1]
		if time == float(right.time):
			return float(right.value)
		# Unity uses infinite tangents for a constant segment. JSON preserves
		# them as strings; never multiply infinity in the Hermite polynomial.
		if _constant_tangent(left.outSlope) or _constant_tangent(right.inSlope):
			return float(left.value)
		var span := float(right.time) - float(left.time)
		var t := (time - float(left.time)) / span
		var t2 := t * t
		var t3 := t2 * t
		return (
			(2.0 * t3 - 3.0 * t2 + 1.0) * float(left.value)
			+ (t3 - 2.0 * t2 + t) * span * float(left.outSlope)
			+ (-2.0 * t3 + 3.0 * t2) * float(right.value)
			+ (t3 - t2) * span * float(right.inSlope)
		)

	return float(keys[-1].value)


static func _constant_tangent(value: Variant) -> bool:
	if value is String:
		return value == "Infinity" or value == "-Infinity"
	return is_inf(float(value))
