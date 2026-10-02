extends Node
## Always-on native distance trail; wind buffs tint new births and add run-frame dust.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var actor: CharacterBody2D
var settings: Dictionary
var trail: Node2D
var previous_normalized_time := 1.0


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "wind_trail.json")
	previous_normalized_time = float(settings.previous_normalized_time)
	process_priority = 410


func _process(_delta: float) -> void:
	advance()


func advance() -> void:
	var stage: Node = actor.weak_dash.stage
	if not is_instance_valid(stage):
		return
	var anchor: Node2D = actor.stamina_feedback.anchor
	if not is_instance_valid(trail):
		trail = stage.spawn_effect(
			settings.trail, anchor.global_position, 0.0, false, anchor, false
		)
	var ratio: float = actor.wind_buff.ratio
	if ratio == 0.0:
		return
	for emitter: Node in trail.emitters:
		emitter.start_color_override = Color(1.0, ratio, ratio)
	if actor.wind_buff.level <= 0 or actor.sprite.clip_name != "run" or actor.action_state != "":
		return
	var clip: Dictionary = actor.sprite.clips.run
	var total_frames := roundi(float(clip.rate) * float(clip.length))
	var normalized := fposmod(float(actor.sprite.elapsed) / float(clip.length), 1.0)
	for frame: float in settings.frames:
		var target := frame / float(total_frames)
		# Match the source comparison, including its lack of wrap-around/frame-zero emission.
		if previous_normalized_time < target and normalized >= target:
			var dust: Node2D = stage.spawn_effect(
				settings.dust, anchor.global_position, 0.0, false, null, false
			)
			dust.scale.x = actor.facing
	previous_normalized_time = normalized


func _exit_tree() -> void:
	if is_instance_valid(trail) and not trail.is_queued_for_deletion():
		trail.hide()
		trail.queue_free()
