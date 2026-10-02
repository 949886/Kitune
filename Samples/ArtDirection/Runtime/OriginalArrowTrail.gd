extends Line2D
## Original TrailRenderer texture, width curve, gradient, spacing and expiration.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Values = preload("res://Samples/ArtDirection/Runtime/UnityParticleValues.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const UNITS := 16.0

var anchor: Node2D
var source: Dictionary
var samples: Array[Dictionary] = []
var clock := 0.0
var previous_position := Vector2.ZERO
var distance_remainder := 0.0


func configure(target: Node2D, data: Dictionary, sort_depth: Callable) -> void:
	anchor = target
	source = data.renderer
	var parameters: Dictionary = source.m_Parameters
	assert(parameters.textureMode == 0 and parameters.alignment == 0)
	assert(parameters.numCornerVertices == 0 and parameters.numCapVertices == 0)
	width = float(parameters.widthMultiplier) * UNITS
	width_curve = Curve.new()
	for key: Dictionary in parameters.widthCurve.m_Curve:
		assert(int(key.weightedMode) == 0)
		width_curve.add_point(Vector2(key.time, key.value), key.inSlope, key.outSlope)
	gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	var stops: Array[float] = []
	var colors: Dictionary = parameters.colorGradient
	for channel in ["color", "alpha"]:
		var count := int(colors.m_NumColorKeys if channel == "color" else colors.m_NumAlphaKeys)
		var prefix := "ctime" if channel == "color" else "atime"
		for index in count:
			var time := float(colors[prefix + str(index)]) / 65535.0
			if time not in stops:
				stops.append(time)
	stops.sort()
	for time in stops:
		gradient.add_point(time, Values.gradient(colors, time))
	texture = load(Assets.ROOT + "Projectiles/" + data.texture.path)
	texture_mode = Line2D.LINE_TEXTURE_STRETCH
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if int(data.texture.filter) == 0
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	material = ShaderMaterial.new()
	material.shader = Glow
	MaterialSettings.configure(material, data.material, get_viewport().use_hdr_2d)
	z_as_relative = false
	z_index = sort_depth.call([source.m_SortingLayer, source.m_SortingOrder])
	top_level = true
	global_transform = Transform2D.IDENTITY
	previous_position = anchor.global_position
	samples.append({"point": previous_position, "time": 0.0})
	process_priority = 440


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	var point := anchor.global_position
	var distance := previous_position.distance_to(point)
	var spacing := float(source.m_MinVertexDistance) * UNITS
	assert(spacing > 0.0)
	if source.m_Emitting and distance > 0.0:
		var total := distance_remainder + distance
		for index in floori(total / spacing):
			var fraction := ((index + 1) * spacing - distance_remainder) / distance
			samples.append(
				{"point": previous_position.lerp(point, fraction), "time": clock + delta * fraction}
			)
		distance_remainder = fmod(total, spacing)
	clock += delta
	previous_position = point
	while not samples.is_empty() and clock - float(samples[0].time) > float(source.m_Time):
		samples.pop_front()
	var vertices := PackedVector2Array()
	if source.m_Emitting:
		vertices.append(point)
	for index in range(samples.size() - 1, -1, -1):
		var previous: Vector2 = samples[index].point
		if vertices.is_empty() or not vertices[-1].is_equal_approx(previous):
			vertices.append(previous)
	points = vertices
