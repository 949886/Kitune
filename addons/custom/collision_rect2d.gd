@tool
extends StaticBody2D
class_name CollisionRect2D
## A centered rectangle whose drawing and static collision share the same size.
## The Custom editor plugin supplies resize handles for this reusable node.

# Share the size constraint with the editor so inspector and handle edits agree.
const MIN_SIZE := 4.0

@export var size := Vector2(128.0, 32.0):
	set(value):
		size = Vector2(maxf(value.x, MIN_SIZE), maxf(value.y, MIN_SIZE))
		_update_shape()
		queue_redraw()
@export var fill_color := Color(0.14, 0.17, 0.24, 1.0):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.35, 0.45, 0.65, 1.0):
	set(value):
		edge_color = value
		queue_redraw()

@export var edge_width := 4.0:
	set(value):
		edge_width = maxf(value, 0.0)
		queue_redraw()

var _collision_shape: CollisionShape2D
var _rectangle := RectangleShape2D.new()

func _ready() -> void:
	# Initialize before attaching the resource to the physics body so a newly
	# added node already has the correct collider, without waiting for a frame.
	_rectangle.size = size
	_collision_shape = get_node_or_null("CollisionShape2D")
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)
		if Engine.is_editor_hint():
			# Native canvas picking understands CollisionShape2D's full rectangle.
			# Owning the helper lets the editor resolve that hit to this component,
			# without adding the generated child to the surrounding scene's owner.
			_collision_shape.owner = self
	# Keep a private shape per instance, even when a root scene contains a saved
	# collider. Exported size remains the source of truth on every scene load.
	_collision_shape.shape = _rectangle
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, fill_color)
	if edge_width > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(edge_width, size.y))), edge_color)

func _update_shape() -> void:
	if _collision_shape == null:
		return
	if Engine.is_editor_hint():
		_rectangle.size = size
	else:
		# Runtime resizing may be triggered by an Area2D physics signal. Updating
		# after query flushing keeps the shape change safe in that signal chain.
		_rectangle.set_deferred("size", size)
