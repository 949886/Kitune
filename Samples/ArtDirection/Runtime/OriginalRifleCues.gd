extends Node2D
## Source LineRenderer widths, gradients, gun anchors and shrinking shot trail.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")

var actor: CharacterBody2D
var settings: Dictionary
var binding: Dictionary
var lines: Dictionary = {}
var local_poses: Dictionary = {}
var tracer_elapsed := 0.0
var tracer_distance := 0.0
var blink_wait := 0.0
var blink_timer := 0.0
var blink_red := false


func configure(enemy: CharacterBody2D, source: Dictionary) -> void:
	actor = enemy
	settings = source
	binding = (
		actor.data.rifle_binding
		if actor.data.has("rifle_binding")
		else settings.actors[str(int(actor.data.go))]
	)
	for key in ["aim", "tracer"]:
		var data: Dictionary = binding[key]
		var line := Line2D.new()
		var parameters: Dictionary = data.parameters
		line.width = float(parameters.widthMultiplier) * actor.PIXELS_PER_UNIT
		var curve := Curve.new()
		for point: Dictionary in parameters.widthCurve.m_Curve:
			curve.add_point(Vector2(point.time, point.value), point.inSlope, point.outSlope)
		line.width_curve = curve
		line.gradient = _gradient(parameters.colorGradient)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.round_precision = maxi(1, int(parameters.numCapVertices))
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if data.texture != null:
			line.texture = load(Assets.ROOT + data.texture.path)
			line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.z_index = actor.ranged_presentation.sort_depth.call(data.sort)
		var source_material: Dictionary = data.material
		var floats: Dictionary = source_material.floats
		# Both source lines have inactive fade thresholds; the shot uses the same
		# verified AllIn1 emission formula as the imported emissive sprites.
		assert(float(floats.get("_FadeAmount", -1.0)) < 0.0)
		var material := ShaderMaterial.new()
		material.shader = Glow
		MaterialSettings.configure(
			material,
			{
				"color": source_material.color,
				"alpha": floats._Alpha,
				"keywords": source_material.keywords,
				"glow_color": source_material.glow_color,
				"glow": floats._Glow,
				"glow_global": floats.get("_GlowGlobal", 1.0)
			},
			actor.get_viewport().use_hdr_2d
		)
		line.material = material
		line.top_level = true
		line.z_as_relative = false
		add_child(line)
		line.hide()
		lines[key] = line
		var anchor: Transform2D = actor.base_transforms[data.anchor_go]
		local_poses[key] = anchor.affine_inverse() * Assets.matrix(data.transform)
	process_priority = 440


func _process(delta: float) -> void:
	sync()
	if lines.tracer.visible:
		tracer_elapsed += delta
		var fraction := clampf(tracer_elapsed / float(settings.tracer_time), 0.0, 1.0)
		lines.tracer.points = PackedVector2Array(
			[Vector2(tracer_distance * fraction, 0), Vector2(tracer_distance, 0)]
		)
		lines.tracer.visible = fraction < 1.0 and actor.ranged_presentation.aiming


func sync() -> void:
	# These source LineRenderers are children of RotationHolder. Top-level
	# transforms keep their world pose, while visibility still follows the holder.
	visible = actor.ranged_presentation.aiming
	for key in lines:
		var source: Dictionary = binding[key]
		lines[key].global_transform = (
			actor.visuals[source.anchor_go].global_transform * local_poses[key]
		)


func begin_aim() -> void:
	blink_wait = 0.0
	blink_timer = 0.0
	blink_red = true
	lines.aim.show()


func advance_blink(delta: float, duration: float) -> void:
	blink_wait -= delta
	if blink_wait > 0.0:
		return
	blink_red = not blink_red
	var range: Dictionary = actor.data.profile.AttackConfirmBlitRange
	var interval := lerpf(float(range.y), float(range.x), clampf(blink_timer / duration, 0, 1))
	blink_timer += interval
	blink_wait = interval
	lines.aim.material.set_shader_parameter(
		"material_tint", Color.RED if blink_red else Color.WHITE
	)


func set_aim_distance(distance: float) -> void:
	lines.aim.points = PackedVector2Array([Vector2.ZERO, Vector2(distance, 0)])


func fire(distance: float) -> void:
	lines.aim.hide()
	tracer_elapsed = 0.0
	tracer_distance = distance
	lines.tracer.points = PackedVector2Array([Vector2.ZERO, Vector2(distance, 0)])
	lines.tracer.show()


func stop() -> void:
	for line: Line2D in lines.values():
		line.hide()


func _gradient(source: Dictionary) -> Gradient:
	var color_stops := Gradient.new()
	var alpha_stops := Gradient.new()
	color_stops.offsets = PackedFloat32Array()
	color_stops.colors = PackedColorArray()
	alpha_stops.offsets = PackedFloat32Array()
	alpha_stops.colors = PackedColorArray()
	var offsets: Array[float] = []
	for index in int(source.m_NumColorKeys):
		var key: Dictionary = source["key%d" % index]
		var time := float(source["ctime%d" % index]) / 65535.0
		color_stops.add_point(time, Color(key.r, key.g, key.b))
		offsets.append(time)
	for index in int(source.m_NumAlphaKeys):
		var time := float(source["atime%d" % index]) / 65535.0
		alpha_stops.add_point(time, Color(1, 1, 1, source["key%d" % index].a))
		offsets.append(time)
	var result := Gradient.new()
	result.offsets = PackedFloat32Array()
	result.colors = PackedColorArray()
	offsets.sort()
	for time in offsets:
		var color := color_stops.sample(time)
		color.a = alpha_stops.sample(time).a
		if result.get_point_count() == 0 or result.get_offset(result.get_point_count() - 1) != time:
			result.add_point(time, color)
	return result
