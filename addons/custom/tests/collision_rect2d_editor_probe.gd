extends SceneTree
## Exercise the enabled Custom plugin and the editor's actual undo history.
## Run with Godot --headless --editor --path <project> --script <this file>.

const CustomPlugin := preload("res://addons/custom/plugin.gd")
const CollisionRect := preload("res://addons/custom/collision_rect2d.gd")


func _initialize() -> void:
	call_deferred("run")


func find_custom_plugin() -> EditorPlugin:
	for candidate in root.find_children("*", "EditorPlugin", true, false):
		if candidate.get_script() == CustomPlugin:
			return candidate
	return null


func click_canvas(canvas: Control, rect: CollisionRect, local_point: Vector2) -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = viewport.global_canvas_transform * rect.to_global(local_point)
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	# Emitting the actual viewport's signal invokes the native canvas picker
	# and normal plugin dispatch, rather than selecting the node in test code.
	canvas.gui_input.emit(event)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	canvas.gui_input.emit(event)
	await process_frame


func check_canvas_selection(scene_path: String) -> void:
	EditorInterface.open_scene_from_path(scene_path)
	EditorInterface.set_main_screen_editor("2D")
	while EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != scene_path:
		await process_frame
	await process_frame
	var scene := EditorInterface.get_edited_scene_root()
	var rect: CollisionRect = scene if scene is CollisionRect else scene.get_node("Rect")
	var canvases := root.find_children("*", "CanvasItemEditorViewport", true, false)
	assert(canvases.size() == 1)
	var canvas: Control = canvases[0]
	var selection := EditorInterface.get_selection()
	for transformed in [false, true]:
		rect.rotation = 0.45 if transformed else 0.0
		rect.scale = Vector2(1.5, 0.6) if transformed else Vector2.ONE
		# Both points are well away from the origin and resize handles. Start
		# unselected to verify selection works while the custom overlay is hidden.
		for local_point in [Vector2(100, 10), Vector2(-110, -20)]:
			selection.clear()
			await process_frame
			await click_canvas(canvas, rect, local_point)
			assert(selection.get_selected_nodes() == [rect], "Clicking the shape must select CollisionRect2D")
		selection.clear()
		await process_frame
		await click_canvas(canvas, rect, Vector2(200, 0))
		assert(selection.get_selected_nodes().is_empty(), "Clicks outside the rectangle must not select it")
	# The helper's editor ownership must not add children to the surrounding
	# scene. Root rectangles may save their collider; _ready reuses that child.
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(packed.get_state().get_node_count() == 2)
	rect.rotation = 0.0
	rect.scale = Vector2.ONE
	selection.clear()


func run() -> void:
	assert(Engine.is_editor_hint(), "Run this probe with --editor")
	# Wait for normal editor startup; manually constructing an EditorPlugin
	# bypasses its registration and cannot verify the project's enabled plugin.
	var plugin: EditorPlugin = find_custom_plugin()
	while plugin == null or EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
		plugin = find_custom_plugin()
	var fixture := Node2D.new()
	root.add_child(fixture)
	var rect := CollisionRect.new()
	fixture.add_child(rect)
	var unrelated := Node2D.new()
	fixture.add_child(unrelated)
	assert(plugin._handles(rect) and not plugin._handles(unrelated))
	plugin._edit(rect)
	var overlay: RefCounted = plugin._overlays[0]
	assert(overlay._edited_rect == rect)
	overlay._begin_drag(overlay.Handle.RIGHT)
	overlay._drag_current_size = Vector2(256, 32)
	overlay._drag_current_position = Vector2(64, 0)
	overlay._apply_resize(rect, overlay._drag_current_size, overlay._drag_current_position)
	overlay._finish_drag()
	assert(rect.size == Vector2(256, 32) and rect.position == Vector2(64, 0))
	var manager := plugin.get_undo_redo()
	var history_id := manager.get_object_history_id(rect)
	var history := manager.get_history_undo_redo(history_id)
	assert(history.undo())
	assert(rect.size == Vector2(128, 32) and rect.position == Vector2.ZERO)
	assert(rect.get_node("CollisionShape2D").shape.size == rect.size)
	assert(history.redo())
	assert(rect.size == Vector2(256, 32) and rect.position == Vector2(64, 0))
	assert(rect.get_node("CollisionShape2D").shape.size == rect.size)
	# A different selection must release the old rectangle's resize handles.
	plugin._edit(unrelated)
	assert(overlay._edited_rect == null)
	manager.clear_history(history_id)
	plugin._make_visible(false)
	fixture.queue_free()
	await process_frame
	await check_canvas_selection("res://addons/custom/tests/fixtures/collision_rect2d_selection.tscn")
	await check_canvas_selection("res://addons/custom/tests/fixtures/collision_rect2d_root_selection.tscn")
	print("COLLISION_RECT_EDITOR_PASS: native area selection, root scene, transforms, resize undo/redo")
	quit()
