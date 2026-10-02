extends Node2D
## Spawn and route order come from scene markers. This only exposes their current
## positions to the study's shared actor/checkpoint/UI logic.

@export var spawn_marker: Marker2D
@export var objective_root: Node2D
@export var checkpoint_root: Node2D


func apply_to(profile: Dictionary) -> void:
	assert(spawn_marker != null and objective_root != null)
	profile.spawn = [spawn_marker.global_position.x, spawn_marker.global_position.y]
	profile.objectives = []
	for child: Node in objective_root.get_children():
		if child.has_method("objective"):
			profile.objectives.append(child.objective())
	assert(not profile.objectives.is_empty(), "Add objective markers to the route")
	profile.checkpoints = []
	if checkpoint_root != null:
		for marker: Marker2D in checkpoint_root.get_children():
			profile.checkpoints.append([marker.global_position.x, marker.global_position.y])
