@tool
extends StaticBody2D
class_name TutorialGate

@export var controller_path: NodePath
@export var open_on_step_id := ""
@export var size := Vector2(28.0, 132.0):
	set(value):
		size = value
		_update_shape()
		queue_redraw()
@export var closed_color := Color(0.45, 0.88, 1.0, 0.95):
	set(value):
		closed_color = value
		queue_redraw()
@export var inner_color := Color(0.08, 0.15, 0.2, 0.92):
	set(value):
		inner_color = value
		queue_redraw()
@export var open_offset := Vector2(0.0, -56.0)

var _collision_shape: CollisionShape2D
var _is_open := false

func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape2D")
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)

	_update_shape()

	var controller: TutorialProgressController = _resolve_controller()
	if controller != null and not controller.is_connected(&"step_completed", Callable(self, "_on_step_completed")):
		controller.connect(&"step_completed", Callable(self, "_on_step_completed"))

	queue_redraw()

func _resolve_controller() -> TutorialProgressController:
	if not controller_path.is_empty():
		return get_node_or_null(controller_path) as TutorialProgressController
	return get_node_or_null("../../ProgressController") as TutorialProgressController

func _draw() -> void:
	if _is_open:
		return

	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, closed_color)
	draw_rect(Rect2(rect.position + Vector2(4.0, 4.0), rect.size - Vector2(8.0, 8.0)), inner_color)

func _on_step_completed(step_id: String) -> void:
	if step_id != open_on_step_id or _is_open:
		return
	open_gate()

func open_gate() -> void:
	if _is_open:
		return

	_is_open = true
	if _collision_shape != null:
		# Step completion can be emitted from Area2D.body_entered while the
		# physics server flushes overlaps. Disable only after those queries finish.
		_collision_shape.set_deferred("disabled", true)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + open_offset, 0.18)
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

func _update_shape() -> void:
	if _collision_shape == null:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	_collision_shape.shape = rectangle
