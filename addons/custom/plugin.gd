@tool
extends EditorPlugin
## Route 2D editing to each custom node's overlay controller.

const CollisionRectOverlay := preload("res://addons/custom/collision_rect2d_overlay.gd")

var _overlays: Array[RefCounted]

func _enter_tree() -> void:
	set_force_draw_over_forwarding_enabled()
	_overlays = [CollisionRectOverlay.new(self)]
	for overlay in _overlays:
		overlay.enter_tree()

func _exit_tree() -> void:
	for overlay in _overlays:
		overlay.exit_tree()
	_overlays.clear()

func _handles(object: Object) -> bool:
	for overlay in _overlays:
		if overlay.handles(object):
			return true
	return false

func _edit(object: Object) -> void:
	for overlay in _overlays:
		# Every controller must see the selection to clear a previous target
		# when the user switches to a node handled by another controller.
		overlay.edit(object)

func _make_visible(visible: bool) -> void:
	for overlay in _overlays:
		overlay.make_visible(visible)

func _forward_canvas_force_draw_over_viewport(control: Control) -> void:
	for overlay in _overlays:
		overlay.draw(control)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	for overlay in _overlays:
		if overlay.gui_input(event):
			return true
	return false
