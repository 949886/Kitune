extends Node2D
## Mirror live renderer state; the water camera must never run particle simulation.

const Effect = preload("res://Samples/ArtDirection/Runtime/OriginalParticleEffect.gd")

var emitters: Array[Dictionary] = []
var pairs: Dictionary = {}
var lighting: Node


func configure(stage: Node2D, water_lighting: Node) -> void:
	lighting = water_lighting
	stage.effect_started.connect(_track_effect)
	# A water view can be attached after an effect has already started.
	for child: Node in stage.get_children():
		if child is Effect:
			_track_effect(child)


func _track_effect(effect: Node2D) -> void:
	for emitter: Node in effect.emitters:
		emitters.append({"source": weakref(emitter), "material": null})


func sync() -> void:
	var alive: Dictionary = {}
	for index in range(emitters.size() - 1, -1, -1):
		var entry: Dictionary = emitters[index]
		var emitter: Node = entry.source.get_ref()
		if not is_instance_valid(emitter) or emitter.is_queued_for_deletion():
			emitters.remove_at(index)
			continue
		for particle: Dictionary in emitter.particles:
			var original: Sprite2D = particle.visual
			var id := original.get_instance_id()
			alive[id] = true
			if not pairs.has(id):
				pairs[id] = _create_copy(original, emitter, entry)
			var copy: Sprite2D = pairs[id]
			_sync_sprite(original, copy)
			if emitter.is_shockwave:
				copy.material.set_shader_parameter(
					"age_percent", original.material.get_shader_parameter("age_percent")
				)
	for id: int in pairs.keys():
		if not alive.has(id):
			var copy: Sprite2D = pairs[id]
			# queue_free alone leaves a dead particle visible until frame end.
			copy.hide()
			copy.queue_free()
			pairs.erase(id)


func _create_copy(original: Sprite2D, emitter: Node, entry: Dictionary) -> Sprite2D:
	var copy := Sprite2D.new()
	copy.z_as_relative = false
	add_child(copy)
	if emitter.is_shockwave:
		# Each particle owns its age; screen_texture resolves inside this viewport.
		copy.material = original.material.duplicate()
	elif entry.material != null:
		copy.material = entry.material
	else:
		copy.material = original.material.duplicate()
		copy.material.set_shader_parameter("linear_framebuffer", false)
		lighting.apply_source(
			copy,
			emitter.data.material,
			int(emitter.data.renderer.m_SortingLayerID),
			"particle:" + str(emitter.data.material.name)
		)
		entry.material = copy.material
	return copy


func _sync_sprite(original: Sprite2D, copy: Sprite2D) -> void:
	copy.texture = original.texture
	copy.texture_filter = original.texture_filter
	copy.texture_repeat = original.texture_repeat
	copy.hframes = original.hframes
	copy.vframes = original.vframes
	copy.frame = original.frame
	copy.centered = original.centered
	copy.offset = original.offset
	copy.flip_h = original.flip_h
	copy.flip_v = original.flip_v
	copy.global_transform = original.global_transform
	copy.modulate = original.modulate
	copy.self_modulate = original.self_modulate
	copy.z_index = original.z_index
	copy.visible = original.is_visible_in_tree()
