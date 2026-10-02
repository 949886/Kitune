@tool
class_name CollisionRect2DOverlay
extends RefCounted
## Eight resize handles with transform-aware dragging and one undo action per drag.

const CollisionRect := preload("res://addons/custom/collision_rect2d.gd")

const OUTLINE_COLOR := Color(0.58, 0.78, 1.0, 0.95)
const HANDLE_COLOR := Color(0.16, 0.22, 0.32, 1.0)
const HANDLE_HIGHLIGHT_COLOR := Color(0.95, 0.98, 1.0, 1.0)
const HANDLE_BORDER_COLOR := Color(0.58, 0.78, 1.0, 1.0)
const HANDLE_SIZE := 10.0
const HANDLE_HIT_RADIUS := 12.0

enum Handle {
	NONE = -1,
	TOP_LEFT,
	TOP,
	TOP_RIGHT,
	RIGHT,
	BOTTOM_RIGHT,
	BOTTOM,
	BOTTOM_LEFT,
	LEFT,
}

# Normalized directions describe both handle positions and the edges they move.
# Corners take priority during hit testing when a small rectangle's handles overlap.
const HANDLE_DIRECTIONS := {
	Handle.TOP_LEFT: Vector2(-1.0, -1.0),
	Handle.TOP: Vector2(0.0, -1.0),
	Handle.TOP_RIGHT: Vector2(1.0, -1.0),
	Handle.RIGHT: Vector2(1.0, 0.0),
	Handle.BOTTOM_RIGHT: Vector2(1.0, 1.0),
	Handle.BOTTOM: Vector2(0.0, 1.0),
	Handle.BOTTOM_LEFT: Vector2(-1.0, 1.0),
	Handle.LEFT: Vector2(-1.0, 0.0),
}
const HIT_TEST_ORDER := [
	Handle.TOP_LEFT, Handle.TOP_RIGHT, Handle.BOTTOM_RIGHT, Handle.BOTTOM_LEFT,
	Handle.TOP, Handle.RIGHT, Handle.BOTTOM, Handle.LEFT,
]

var _plugin: EditorPlugin
var _edited_rect: CollisionRect
var _hover_handle := Handle.NONE
var _drag_handle := Handle.NONE
var _drag_start_size := Vector2.ZERO
var _drag_start_position := Vector2.ZERO
var _drag_start_transform := Transform2D.IDENTITY
var _drag_start_canvas_inverse := Transform2D.IDENTITY
var _drag_current_size := Vector2.ZERO
var _drag_current_position := Vector2.ZERO

func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin

func enter_tree() -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	if selection != null and not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

func exit_tree() -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	if selection != null and selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	_reset_interaction_state()
	_plugin.update_overlays()

func handles(object: Object) -> bool:
	return _get_rect_target(object) != null

func _get_rect_target(object: Object) -> CollisionRect:
	if object is CollisionRect:
		return object
	if object is CollisionShape2D:
		var parent: Node = object.get_parent()
		if parent is CollisionRect and parent._collision_shape == object:
			return parent
	return null

func edit(object: Object) -> void:
	_edited_rect = _get_rect_target(object)
	if _edited_rect != null and object != _edited_rect:
		# When the rectangle itself is the edited scene root, native picking
		# selects its owned helper. Normalize selection after plugin dispatch so
		# the inspector and canvas tools continue to edit the rectangle itself.
		call_deferred("_select_rect_parent", object, _edited_rect)
	_reset_interaction_state()
	_plugin.update_overlays()

func _select_rect_parent(shape: CollisionShape2D, rect: CollisionRect) -> void:
	if not is_instance_valid(shape) or not is_instance_valid(rect):
		return
	var selection := _plugin.get_editor_interface().get_selection()
	if not selection.get_selected_nodes().has(shape):
		return
	selection.remove_node(shape)
	selection.add_node(rect)
	if selection.get_selected_nodes().size() == 1:
		_plugin.get_editor_interface().edit_node(rect)

func make_visible(visible: bool) -> void:
	if not visible:
		_edited_rect = null
	_reset_interaction_state()
	_plugin.update_overlays()

func draw(overlay: Control) -> void:
	if not _can_draw_overlay():
		return

	var handles_map := _get_handle_positions(_edited_rect)
	if handles_map.is_empty():
		return

	var corners := PackedVector2Array([
		handles_map[Handle.TOP_LEFT],
		handles_map[Handle.TOP_RIGHT],
		handles_map[Handle.BOTTOM_RIGHT],
		handles_map[Handle.BOTTOM_LEFT],
		handles_map[Handle.TOP_LEFT],
	])
	overlay.draw_polyline(corners, OUTLINE_COLOR, 2.0, true)

	for handle_id in handles_map.keys():
		var point: Vector2 = handles_map[handle_id]
		var color := HANDLE_HIGHLIGHT_COLOR if handle_id == _drag_handle or handle_id == _hover_handle else HANDLE_COLOR
		var rect := Rect2(point - Vector2.ONE * HANDLE_SIZE * 0.5, Vector2.ONE * HANDLE_SIZE)
		overlay.draw_rect(rect, color)
		overlay.draw_rect(rect, HANDLE_BORDER_COLOR, false, 2.0)

func gui_input(event: InputEvent) -> bool:
	if not _can_draw_overlay():
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var handle := _pick_handle(event.position)
			if handle == Handle.NONE:
				return false
			_begin_drag(handle)
			_update_drag(event.position)
			return true
		if _drag_handle != Handle.NONE:
			_finish_drag()
			return true

	if event is InputEventMouseMotion:
		if _drag_handle != Handle.NONE:
			_update_drag(event.position)
			return true

		var next_hover := _pick_handle(event.position)
		if next_hover != _hover_handle:
			_hover_handle = next_hover
			_plugin.update_overlays()

	return false

func _on_selection_changed() -> void:
	_plugin.update_overlays()

func _can_draw_overlay() -> bool:
	return is_instance_valid(_edited_rect) and is_instance_valid(_edited_rect.get_viewport())

func _reset_interaction_state() -> void:
	_hover_handle = Handle.NONE
	_drag_handle = Handle.NONE
	_drag_start_size = Vector2.ZERO
	_drag_start_position = Vector2.ZERO
	_drag_start_transform = Transform2D.IDENTITY
	_drag_start_canvas_inverse = Transform2D.IDENTITY
	_drag_current_size = Vector2.ZERO
	_drag_current_position = Vector2.ZERO

func _begin_drag(handle: int) -> void:
	_drag_handle = handle
	_hover_handle = handle
	_drag_start_size = _edited_rect.size
	_drag_start_position = _edited_rect.position
	_drag_start_transform = _edited_rect.transform
	# Freeze the original inverse: the node's center moves as we resize it.
	# Recomputing it during dragging would feed that movement into the next edit.
	_drag_start_canvas_inverse = _get_editor_canvas_transform(_edited_rect).affine_inverse()
	_drag_current_size = _drag_start_size
	_drag_current_position = _drag_start_position

func _update_drag(viewport_position: Vector2) -> void:
	var local_mouse := _drag_start_canvas_inverse * viewport_position
	var result := _build_drag_result(local_mouse)
	_drag_current_size = result["size"]
	_drag_current_position = result["position"]
	_apply_resize(_edited_rect, _drag_current_size, _drag_current_position)
	_plugin.update_overlays()

func _finish_drag() -> void:
	var old_size := _drag_start_size
	var old_position := _drag_start_position
	var new_size := _drag_current_size
	var new_position := _drag_current_position

	if not old_size.is_equal_approx(new_size) or not old_position.is_equal_approx(new_position):
		var undo_redo := _plugin.get_undo_redo()
		undo_redo.create_action("Resize CollisionRect2D")
		undo_redo.add_do_property(_edited_rect, "size", new_size)
		undo_redo.add_do_property(_edited_rect, "position", new_position)
		undo_redo.add_undo_property(_edited_rect, "size", old_size)
		undo_redo.add_undo_property(_edited_rect, "position", old_position)
		undo_redo.commit_action()

	_reset_interaction_state()
	_plugin.update_overlays()

func _pick_handle(viewport_position: Vector2) -> int:
	var handles_map := _get_handle_positions(_edited_rect)
	for handle_id in HIT_TEST_ORDER:
		if not handles_map.has(handle_id):
			continue
		if handles_map[handle_id].distance_to(viewport_position) <= HANDLE_HIT_RADIUS:
			return handle_id

	return Handle.NONE

func _get_handle_positions(rect: CollisionRect) -> Dictionary:
	if not is_instance_valid(rect):
		return {}

	var half_size: Vector2 = rect.size * 0.5
	var transform: Transform2D = _get_editor_canvas_transform(rect)

	var positions := {}
	for handle_id in HANDLE_DIRECTIONS:
		positions[handle_id] = transform * (half_size * HANDLE_DIRECTIONS[handle_id])
	return positions

func _get_editor_canvas_transform(rect: CollisionRect) -> Transform2D:
	var editor_viewport: SubViewport = _plugin.get_editor_interface().get_editor_viewport_2d()
	if editor_viewport == null:
		return rect.get_global_transform()
	return editor_viewport.global_canvas_transform * rect.get_global_transform()

func _build_drag_result(local_mouse: Vector2) -> Dictionary:
	var left := -_drag_start_size.x * 0.5
	var right := _drag_start_size.x * 0.5
	var top := -_drag_start_size.y * 0.5
	var bottom := _drag_start_size.y * 0.5

	var direction: Vector2 = HANDLE_DIRECTIONS.get(_drag_handle, Vector2.ZERO)
	if direction.x < 0.0:
		left = minf(local_mouse.x, right - CollisionRect.MIN_SIZE)
	elif direction.x > 0.0:
		right = maxf(local_mouse.x, left + CollisionRect.MIN_SIZE)
	if direction.y < 0.0:
		top = minf(local_mouse.y, bottom - CollisionRect.MIN_SIZE)
	elif direction.y > 0.0:
		bottom = maxf(local_mouse.y, top + CollisionRect.MIN_SIZE)

	var new_size: Vector2 = Vector2(right - left, bottom - top)
	var center_offset: Vector2 = Vector2((left + right) * 0.5, (top + bottom) * 0.5)
	# Move the center in parent space to hold the opposite edge/corner fixed,
	# including nodes with rotation or nonuniform scale.
	var new_position: Vector2 = _drag_start_transform * center_offset

	return {
		"size": new_size,
		"position": new_position,
	}

func _apply_resize(rect: CollisionRect, new_size: Vector2, new_position: Vector2) -> void:
	rect.position = new_position
	rect.size = new_size
