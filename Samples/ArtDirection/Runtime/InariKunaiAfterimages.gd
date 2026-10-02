extends Node
## Native timer discards overshoot and emits at most one ghost per Update.

const Ghost = preload("res://Samples/ArtDirection/Runtime/InariKunaiGhost.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const UNITS := 16.0

var flight: Node2D
var stage: Node
var source: Dictionary
var ghosts: Array[Sprite2D] = []
var timer := 0.0
var last_spawn := Vector2.ZERO


func configure(effect: Node2D, owner_stage: Node) -> void:
	flight = effect
	stage = owner_stage
	source = Assets.read_json(Assets.ROOT + "kunai_afterimage.json")
	process_priority = 435


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	for index in range(ghosts.size() - 1, -1, -1):
		if not is_instance_valid(ghosts[index]):
			ghosts.remove_at(index)
			continue
		var ghost: Sprite2D = ghosts[index]
		if ghost.is_queued_for_deletion():
			ghosts.remove_at(index)
		else:
			ghost.advance(delta)
	var target: Sprite2D = flight.follow_actor
	if not is_instance_valid(target) or target.texture == null:
		return
	timer = PackedFloat32Array([timer + delta])[0]
	if timer < float(source.spawnInterval):
		return
	var distance := float(source.minDistance) * UNITS
	if (
		source.useDistanceGate
		and target.global_position.distance_squared_to(last_spawn) < distance * distance
	):
		return
	timer = 0.0
	last_spawn = target.global_position
	var ghost := Ghost.new()
	stage.add_child(ghost)
	ghost.configure(target, stage, delta)
	ghosts.append(ghost)
	stage.kunai_ghost_started.emit(ghost)


func clear() -> void:
	for ghost: Variant in ghosts:
		if is_instance_valid(ghost):
			ghost.hide()
			ghost.queue_free()
	ghosts.clear()


func _exit_tree() -> void:
	clear()
