extends RefCounted
## Serialized MinMaxCurve/MinMaxGradient values; random factors persist per particle.

const SourceCurve = preload("UnityCurve.gd")


static func number(source: Dictionary, time := 0.0, random := 0.0) -> float:
	match int(source.minMaxState):
		0:
			return float(source.scalar)
		1:
			return SourceCurve.evaluate(source.maxCurve, time) * float(source.scalar)
		2:
			return (
				lerpf(
					SourceCurve.evaluate(source.minCurve, time),
					SourceCurve.evaluate(source.maxCurve, time),
					random
				)
				* float(source.scalar)
			)
		3:
			return lerpf(float(source.minScalar), float(source.scalar), random)
	assert(false, "Unsupported source particle curve mode")
	return 0.0


static func color(source: Dictionary, time := 0.0, random := 0.0) -> Color:
	match int(source.minMaxState):
		0:
			return rgba(source.maxColor)
		1:
			return gradient(source.maxGradient, time)
		2:
			return rgba(source.minColor).lerp(rgba(source.maxColor), random)
		3:
			return gradient(source.minGradient, time).lerp(
				gradient(source.maxGradient, time), random
			)
		4:
			return gradient(source.maxGradient, random)
	assert(false, "Unsupported source particle color mode")
	return Color.WHITE


static func rgba(value: Dictionary) -> Color:
	return Color(value.r, value.g, value.b, value.a)


static func gradient(source: Dictionary, time: float) -> Color:
	var result := Color.WHITE
	for channel in ["color", "alpha"]:
		var count := int(source.m_NumColorKeys if channel == "color" else source.m_NumAlphaKeys)
		var prefix := "ctime" if channel == "color" else "atime"
		var previous := 0
		var next := 0
		for index in count:
			next = index
			if time <= float(source[prefix + str(index)]) / 65535.0:
				break
			previous = index
		var first := float(source[prefix + str(previous)]) / 65535.0
		var last := float(source[prefix + str(next)]) / 65535.0
		var weight := clampf((time - first) / (last - first), 0, 1) if last > first else 0.0
		if int(source.m_Mode) == 1:
			weight = 0.0
		var value := rgba(source["key" + str(previous)]).lerp(
			rgba(source["key" + str(next)]), weight
		)
		if channel == "color":
			result.r = value.r
			result.g = value.g
			result.b = value.b
		else:
			result.a = value.a
	return result


static func vector(value: Dictionary) -> Vector3:
	return Vector3(value.x, value.y, value.z)


static func transform(rows: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(rows[0][0], rows[1][0], rows[2][0]),
			Vector3(rows[0][1], rows[1][1], rows[2][1]),
			Vector3(rows[0][2], rows[1][2], rows[2][2])
		),
		Vector3(rows[0][3], rows[1][3], rows[2][3])
	)
