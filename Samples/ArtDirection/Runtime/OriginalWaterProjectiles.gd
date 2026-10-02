extends Node2D
## WaterTextureFeature includes arrows and retiring kunai, without cloned physics.

const Arrow = preload("res://Samples/ArtDirection/Runtime/OriginalArrow.gd")
const KunaiFade = preload("res://Samples/ArtDirection/Runtime/InariKunaiFade.gd")
const KunaiGhost = preload("res://Samples/ArtDirection/Runtime/InariKunaiGhost.gd")

var pairs: Dictionary = {}
var kunai_pairs: Dictionary = {}
var lighting: Node


func configure(stage: Node2D, water_lighting: Node = null) -> void:
	lighting = water_lighting
	stage.arrow_started.connect(_track_arrow)
	stage.kunai_retired.connect(_track_kunai)
	stage.kunai_ghost_started.connect(_track_kunai)
	for child: Node in stage.get_children():
		if child is Arrow:
			_track_arrow(child)
		elif child is KunaiFade or child is KunaiGhost:
			_track_kunai(child)


func _track_kunai(original: Sprite2D) -> void:
	if kunai_pairs.has(original.get_instance_id()):
		return
	var copy := Sprite2D.new()
	copy.z_as_relative = false
	add_child(copy)
	original.apply_material(copy, lighting)
	kunai_pairs[original.get_instance_id()] = {"source": weakref(original), "copy": copy}
	_sync_kunai(original, copy)


func _sync_kunai(original: Sprite2D, copy: Sprite2D) -> void:
	copy.texture = original.texture
	copy.texture_filter = original.texture_filter
	copy.centered = original.centered
	copy.offset = original.offset
	copy.flip_h = original.flip_h
	copy.flip_v = original.flip_v
	copy.global_transform = original.global_transform
	copy.modulate = original.modulate
	copy.z_index = original.z_index
	copy.visible = original.is_visible_in_tree()
	copy.material.set_shader_parameter(
		"hit_blend", original.material.get_shader_parameter("hit_blend")
	)


func _track_arrow(arrow: RigidBody2D) -> void:
	var id := arrow.get_instance_id()
	if pairs.has(id):
		return
	# Only plain draw nodes are copied. Arrow physics and trail sample history
	# continue to belong to the gameplay viewport, including during hit-stop.
	var sprite := Sprite2D.new()
	sprite.material = _water_material(arrow.visual.material)
	sprite.z_as_relative = false
	add_child(sprite)
	var trail := Line2D.new()
	trail.material = _water_material(arrow.trail.material)
	trail.z_as_relative = false
	trail.width = arrow.trail.width
	trail.width_curve = arrow.trail.width_curve
	trail.gradient = arrow.trail.gradient
	trail.texture = arrow.trail.texture
	trail.texture_mode = arrow.trail.texture_mode
	trail.texture_filter = arrow.trail.texture_filter
	trail.joint_mode = arrow.trail.joint_mode
	trail.begin_cap_mode = arrow.trail.begin_cap_mode
	trail.end_cap_mode = arrow.trail.end_cap_mode
	add_child(trail)
	pairs[id] = {"source": weakref(arrow), "sprite": sprite, "trail": trail}
	_sync_pair(pairs[id], arrow)


func _water_material(original: ShaderMaterial) -> ShaderMaterial:
	var copy := original.duplicate() as ShaderMaterial
	copy.set_shader_parameter("linear_framebuffer", false)
	return copy


func sync() -> void:
	for id: int in kunai_pairs.keys():
		var pair: Dictionary = kunai_pairs[id]
		var original: Node = pair.source.get_ref()
		if not is_instance_valid(original) or original.is_queued_for_deletion():
			pair.copy.hide()
			pair.copy.queue_free()
			kunai_pairs.erase(id)
		else:
			_sync_kunai(original, pair.copy)
	for id: int in pairs.keys():
		var pair: Dictionary = pairs[id]
		var arrow: Node = pair.source.get_ref()
		if not is_instance_valid(arrow) or arrow.is_queued_for_deletion():
			for copy: Node2D in [pair.sprite, pair.trail]:
				copy.hide()
				copy.queue_free()
			pairs.erase(id)
			continue
		_sync_pair(pair, arrow)


func _sync_pair(pair: Dictionary, arrow: Node2D) -> void:
	var original: Sprite2D = arrow.visual
	var sprite: Sprite2D = pair.sprite
	sprite.texture = original.texture
	sprite.texture_filter = original.texture_filter
	sprite.centered = original.centered
	sprite.offset = original.offset
	sprite.flip_h = original.flip_h
	sprite.flip_v = original.flip_v
	sprite.global_transform = original.global_transform
	sprite.modulate = original.modulate * arrow.modulate
	sprite.self_modulate = original.self_modulate
	sprite.z_index = original.z_index
	sprite.visible = original.is_visible_in_tree()
	var trail: Line2D = pair.trail
	trail.global_transform = arrow.trail.global_transform
	trail.points = arrow.trail.points
	trail.modulate = arrow.trail.modulate * arrow.modulate
	trail.self_modulate = arrow.trail.self_modulate
	trail.z_index = arrow.trail.z_index
	trail.visible = arrow.trail.is_visible_in_tree()
