extends Node
## PlayerWeakMarkPoint and CalculateKeyboardAimLine, driven by source selection order.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const LineShader = preload("res://Samples/ArtDirection/Shaders/OriginalDottedLine.gdshader")

var actor: CharacterBody2D
var settings: Dictionary
var marker := Node2D.new()
var line := Line2D.new()
var visuals: Array[Node2D] = []
var fades: Array[Dictionary] = []
var light: Dictionary
var light_offset := Vector2.ZERO
var previous_id := 0
var line_calculated := false


static func light_source() -> Dictionary:
	var source: Dictionary = Assets.read_json(Assets.ROOT + "target_marker.json")
	var result: Dictionary = source.light.duplicate(true)
	result["enabled"] = false
	result["revision"] = 0
	return result


func configure(owner_node: CharacterBody2D, stage: Node) -> void:
	actor = owner_node
	settings = Assets.read_json(Assets.ROOT + "target_marker.json")
	add_child(marker)
	marker.top_level = true
	marker.hide()
	for item: Dictionary in settings.sprites:
		var visual := Visual.new()
		visual.configure(item)
		marker.add_child(visual)
		visual.z_as_relative = false
		visual.z_index = stage.sort_depth(item.sort)
		stage.lighting.apply_to(visual, item)
		visuals.append(visual)
	light = stage.lighting.runtime_lights[0]
	light_offset = Assets.vec(settings.light.spatial.transform.slice(4, 6))
	add_child(line)
	line.top_level = true
	line.z_as_relative = false
	line.z_index = stage.sort_depth(settings.line.sort)
	line.texture = load(Assets.ROOT + settings.line.texture.path)
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var parameters: Dictionary = settings.line.parameters
	assert(parameters.widthCurve.m_Curve.size() == 1)
	assert(parameters.colorGradient.key0 == parameters.colorGradient.key1)
	line.width = (
		float(parameters.widthMultiplier)
		* float(parameters.widthCurve.m_Curve[0].value)
		* actor.units
	)
	var material := ShaderMaterial.new()
	material.shader = LineShader
	material.set_shader_parameter("linear_framebuffer", stage.lighting.linear_framebuffer)
	material.set_shader_parameter("line_color", Assets.color(settings.line.color))
	var color: Dictionary = parameters.colorGradient.key0
	material.set_shader_parameter("gradient_color", Color(color.r, color.g, color.b, color.a))
	material.set_shader_parameter("dash_length", settings.line.dash_length)
	material.set_shader_parameter("gap_length", settings.line.gap_length)
	material.set_shader_parameter("pixels_per_unit", actor.units)
	line.material = material
	for point: Array in settings.line.initial_points:
		line.add_point(Vector2(point[0], point[1]))
	material.set_shader_parameter("endpoint_depth", settings.line.initial_points[1][2])
	line.hide()
	process_priority = 405


func update_line(target: Node) -> void:
	# PlayerStateMachine calculates endpoints before searching for a new target.
	# A target switch consequently keeps the old endpoints for this update.
	if not is_instance_valid(target):
		if not line_calculated:
			line.global_position = actor.global_position + Assets.vec(settings.line.initial_offset)
		return
	line_calculated = true
	line.material.set_shader_parameter("endpoint_depth", 0.0)
	line.global_position = actor.global_position + actor.body_shape.position
	var end: Vector2 = target.global_position + target.body_shape.position
	line.points = PackedVector2Array([Vector2.ZERO, end - line.global_position])


func update_selection(target: Node, has_ranges: bool, gamepad: bool) -> void:
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	if not has_ranges:
		set_active(false)
		line.hide()
		return
	if previous_id != 0 and previous_id != target_id:
		set_active(false)
		line.hide()
	previous_id = target_id
	if target_id != 0:
		set_active(true)
		marker.global_position = target.global_position + target.body_shape.position
		# Native code only enables the mouse line here. A same-target device
		# switch to gamepad does not explicitly hide an already visible line.
		if not gamepad:
			line.show()
	_sync_light()


func set_active(value: bool, immediate := false) -> void:
	if value == marker.visible:
		return
	if not value and immediate:
		marker.hide()
		_sync_light()
		return
	if value:
		marker.show()
	var start := 0.0 if value else 1.0
	var duration: float = settings.fade_in if value else settings.disappear_time
	for visual: Node2D in visuals:
		visual.modulate.a = start
		fades.append({"visual": visual, "age": 0.0, "duration": duration, "show": value})
	_sync_light()


func advance(delta: float) -> void:
	# Source DOFade uses DOTween's default OutQuad. Overlapping hide requests
	# are intentionally retained; SetActivate does not kill outstanding tweens.
	var remaining: Array[Dictionary] = []
	for fade: Dictionary in fades:
		fade.age += delta
		var progress := 1.0 if fade.duration <= 0.0 else minf(fade.age / fade.duration, 1.0)
		var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
		fade.visual.modulate.a = eased if fade.show else 1.0 - eased
		if progress < 1.0:
			remaining.append(fade)
		elif not fade.show:
			marker.hide()
	fades = remaining
	_sync_light()


func reset() -> void:
	set_active(false, true)
	line.hide()
	previous_id = 0


func _sync_light() -> void:
	var position := marker.global_position + light_offset
	var transform: Array = light.spatial.transform
	if light.enabled == marker.visible and Vector2(transform[4], transform[5]) == position:
		return
	light.enabled = marker.visible
	transform[4] = position.x
	transform[5] = position.y
	light.revision += 1


func _process(delta: float) -> void:
	advance(delta)
