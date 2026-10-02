extends RefCounted
## Native otherRenderers DOFloat requests retain overlapping OutQuad tweens.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var actor: Node
var settings: Dictionary
var values: Dictionary = {}
var tweens: Array[Dictionary] = []
var duration := 0.0
var selected := false


func configure(owner_node: Node, visual_ids: Array, source: Dictionary) -> void:
	actor = owner_node
	settings = source
	duration = float(actor.data.common.OutLineSpeed)
	for go in visual_ids:
		var material := Assets.material_info(actor.visuals[go].current_material)
		values[go] = float(material.base_outline.alpha)
	apply()


func range_changed(contact: bool) -> void:
	# Native range events do not check Selected; the most recent request wins
	# through tween update order even if an earlier selection tween still runs.
	_request(float(settings.in_range if contact else settings.outside))


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	var contact: bool = actor.weakpoint_presentation.contact_in_range
	var target := float(settings.in_range if contact else settings.outside)
	_request(float(settings.selected) if selected else target)


func _request(target: float) -> void:
	tweens.append({"from": values.duplicate(), "to": target, "elapsed": 0.0})


func step(delta: float) -> void:
	var unfinished: Array[Dictionary] = []
	for tween: Dictionary in tweens:
		tween.elapsed = minf(float(tween.elapsed) + delta, duration)
		var progress := 1.0 if duration <= 0.0 else float(tween.elapsed) / duration
		var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
		for go in values:
			values[go] = lerpf(float(tween.from[go]), float(tween.to), eased)
		if tween.elapsed < duration:
			unfinished.append(tween)
	tweens = unfinished
	apply()


func apply() -> void:
	for go in values:
		var visual: Node2D = actor.visuals[go]
		if visual.material is ShaderMaterial:
			visual.material.set_shader_parameter("base_outline_alpha", values[go])
