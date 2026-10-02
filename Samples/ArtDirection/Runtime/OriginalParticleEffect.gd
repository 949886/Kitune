extends Node2D
## A source pooled effect instance; muzzle effects follow the enemy root only.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Emitter = preload("res://Samples/ArtDirection/Runtime/OriginalParticleEmitter.gd")

static var definitions: Dictionary = {}

var sorting: Callable
var follow_actor: Node2D
var emitters: Array[Node] = []
var effect_key := ""
var follow_rotation := false


func on_source_time_scale(value: float) -> void:
	for emitter: Node in emitters:
		emitter.time_scale_override = value


func configure(key: String, sort_depth: Callable, follow: Node2D = null, seed_value := -1) -> void:
	effect_key = key
	sorting = sort_depth
	follow_actor = follow
	if definitions.is_empty():
		definitions = Assets.read_json(Emitter.ROOT + "effects.json")
	var data := definitions
	for index in data.effects[key].emitters.size():
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure(
			data.effects[key].emitters[index],
			self,
			data.gravity_2d,
			randi() if seed_value < 0 else seed_value + index
		)
		emitters.append(emitter)
	process_priority = 420


func _process(_delta: float) -> void:
	if is_instance_valid(follow_actor):
		global_position = follow_actor.global_position
		if follow_rotation:
			global_rotation = follow_actor.global_rotation
	if emitters.all(func(emitter: Node): return not emitter.is_processing()):
		queue_free()
