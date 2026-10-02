@tool
extends Marker2D
## Scene-authored objective. Its position and radius remain editable in Godot.

@export var label := ""
@export_range(0.1, 1000.0) var radius := 20.0:
	set(value):
		radius = value
		queue_redraw()
@export var require_grounded := false
@export var require_climbing := false
@export var climb_id := ""
@export var kunai_anchor: Marker2D


func objective() -> Dictionary:
	var result := {
		"name": label,
		"position": [global_position.x, global_position.y],
		"radius": radius,
		"grounded": require_grounded,
		"climbing": require_climbing,
	}
	if not climb_id.is_empty():
		result.climb_node = climb_id
	if kunai_anchor != null:
		result.kunai_anchor = [kunai_anchor.global_position.x, kunai_anchor.global_position.y]
	return result


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(0.2, 0.9, 0.6, 0.65), 1.0)
