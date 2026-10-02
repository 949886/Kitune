extends Node
## Native outline tween and Eff_Accel: restart on each hit, independent of combat time.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var actor: CharacterBody2D
var anchor := Node2D.new()
var settings: Dictionary
var active := false
var elapsed := 0.0
var effects: Array[WeakRef] = []


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "stamina_feedback.json")
	assert(settings.ease == "OutQuad")
	var offset: Dictionary = actor.tuning.body_offset
	anchor.position = actor.body_shape.position - Vector2(offset.x, -float(offset.y)) * actor.units
	actor.add_child(anchor)
	process_priority = 400


func trigger(current_level := 0, previous_level := 0) -> void:
	# DOTween.Kill leaves the current material value. The level gate happens
	# after cancellation; a decreasing level must not start a replacement tween.
	active = false
	if current_level < previous_level:
		return
	active = true
	elapsed = 0.0
	var stage: Node = actor.weak_dash.stage
	if is_instance_valid(stage):
		var effect: Node2D = stage.spawn_effect(
			settings.effect, anchor.global_position, 0.0, false, anchor, false
		)
		effects.append(weakref(effect))


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	effects = effects.filter(func(entry: WeakRef): return is_instance_valid(entry.get_ref()))
	if not active:
		return
	elapsed = PackedFloat32Array([elapsed + delta])[0]
	var duration := float(actor.combat[settings.duration_parameter])
	var t := 1.0 if duration <= 0.0 else clampf(elapsed / duration, 0.0, 1.0)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	actor.sprite.material.set_shader_parameter(
		"inner_outline_alpha", lerpf(settings.start, settings.end, eased)
	)
	if t >= 1.0:
		active = false


func _exit_tree() -> void:
	# Native Eff_Accel is parented to the player, despite the shared pool.
	for entry: WeakRef in effects:
		var effect: Node2D = entry.get_ref()
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			effect.hide()
			effect.queue_free()
