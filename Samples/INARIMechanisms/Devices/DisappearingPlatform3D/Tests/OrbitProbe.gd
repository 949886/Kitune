extends SceneTree
## Standalone camera/input regression probe. Copy only this device directory and
## run --script res://<device>/Tests/OrbitProbe.gd after an editor import.
## When the repository workshop is present, its real actor input is tested too.
const Platform = preload("../DisappearingPlatform3D.tscn")
const Preview = preload("../Examples/Preview.tscn")
var checks := 0
var failed := false


class InputSink extends Node:
	var received := 0
	func _unhandled_input(_event: InputEvent) -> void:
		received += 1


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func make_platform() -> Node2D:
	var platform: Node2D = Platform.instantiate()
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	root.add_child(platform)
	platform.set_physics_process(false)
	return platform


func key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func button(index: MouseButton, pressed := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.factor = 1.0
	event.position = Vector2(400, 300)
	return event


func motion(relative: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.button_mask = mask
	event.position = Vector2(400, 300)
	return event


func snapshot(platform: Node2D) -> Dictionary:
	return {"transform": platform.camera.transform, "size": platform.camera.size, "projection": platform.camera.projection, "display_position": platform.display.position}


func check_restored(platform: Node2D, original: Dictionary) -> void:
	check(platform.camera.transform == original.transform, "Gameplay camera transform was not restored exactly")
	check(platform.camera.size == original.size, "Gameplay camera size was not restored exactly")
	check(platform.camera.projection == original.projection, "Gameplay projection was not restored exactly")
	check(platform.display.position == original.display_position, "Viewport sprite placement was not restored exactly")
	check(not platform.is_inspecting() and platform._orbit_saved.is_empty(), "Exit retained inspection state")


func node_count(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += node_count(child)
	return count


func run() -> void:
	await check_device_camera()
	await check_preview_input()
	await check_workshop_input()
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_ORBIT_PASS checks=", checks)
	quit(1 if failed else 0)


func check_device_camera() -> void:
	var platform := make_platform()
	var other := make_platform()
	var untouched := snapshot(other)
	# A nondefault host camera must be restored, not merely approximated by the
	# initial editor pose. Orthographic size is retained even in perspective.
	platform.camera.transform = Transform3D(Basis.from_euler(Vector3(0.03, -0.07, 0.01)), Vector3(17, -9, 480))
	platform.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	platform.camera.size = 187.35
	var original := snapshot(platform)
	var original_nodes := node_count(platform)
	var polygon: PackedVector2Array = platform.shape.polygon.duplicate()
	var shadows: Array[MeshInstance3D] = []
	for item: Dictionary in platform.record.visuals:
		if item.sprite == "sharedassets0_446":
			shadows.append(platform.visuals[item.go])
	check(not platform.handle_inspection_input(button(MOUSE_BUTTON_LEFT)), "Normal gameplay input was consumed by inactive orbit API")
	for cycle in 12:
		# Preserve both originally visible and host-hidden shadow states.
		var shadow_visible := cycle % 2 == 0
		for shadow in shadows:
			shadow.visible = shadow_visible
		platform.enter_inspection()
		for shadow in shadows:
			check(not shadow.visible, "Ambient shadow obscures orbit inspection")
		check(platform.is_inspecting(), "Enter did not activate inspection")
		check(platform.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Inspection projection is not orthographic")
		check(platform.display.position == -Vector2(platform.viewport.size) * 0.5, "Orbit origin drifts with halo viewport bounds")
		check((-platform.camera.basis.z).dot(-platform.camera.position.normalized()) > 0.99999, "Camera does not orbit the central platform origin")
		var before: Transform3D = platform.camera.transform
		platform.enter_inspection()
		check(platform.camera.transform == before, "Repeated entry reset the view or overwrote the snapshot")
		check(platform.handle_inspection_input(button(MOUSE_BUTTON_LEFT)), "Inspection mouse button not consumed")
		platform.handle_inspection_input(motion(Vector2(70, 30)))
		check(platform.camera.transform != before, "Drag did not rotate the camera")
		check(absf(platform._orbit_pitch - deg_to_rad(20.0)) > 0.1, "Vertical drag did not change pitch")
		check(absf(platform._orbit_yaw - deg_to_rad(35.0)) > 0.1, "Horizontal drag did not change yaw")
		platform.handle_inspection_input(button(MOUSE_BUTTON_LEFT, false))
		before = platform.camera.transform
		platform.handle_inspection_input(motion(Vector2(100, 100)))
		check(platform.camera.transform == before, "Mouse motion after release continued dragging")
		platform.handle_inspection_input(button(MOUSE_BUTTON_LEFT))
		platform.handle_inspection_input(motion(Vector2(100, 100), 0))
		check(platform.camera.transform == before and platform._orbit_drag_button == MOUSE_BUTTON_NONE, "A missed mouse release left a stale drag")
		platform.handle_inspection_input(button(MOUSE_BUTTON_RIGHT))
		platform.handle_inspection_input(motion(Vector2(700, 10000), MOUSE_BUTTON_MASK_RIGHT))
		check(is_equal_approx(platform._orbit_pitch, platform.ORBIT_PITCH_LIMIT), "Positive pitch limit failed")
		platform.handle_inspection_input(motion(Vector2(700, -10000), MOUSE_BUTTON_MASK_RIGHT))
		check(is_equal_approx(platform._orbit_pitch, -platform.ORBIT_PITCH_LIMIT), "Negative pitch limit failed")
		check(platform.camera.transform.is_finite(), "Extreme drag produced an invalid camera transform")
		platform.handle_inspection_input(motion(Vector2((platform._orbit_yaw - PI) / platform.ORBIT_SENSITIVITY, -platform._orbit_pitch / platform.ORBIT_SENSITIVITY), MOUSE_BUTTON_MASK_RIGHT))
		check(platform.camera.position.z < -499.0, "Free orbit cannot reach the rear of the model")
		before = platform.camera.transform
		platform.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		platform.handle_inspection_input(motion(Vector2(60, 40), MOUSE_BUTTON_MASK_RIGHT))
		check(platform.camera.transform == before, "Focus loss did not cancel the active drag")
		for _step in 100:
			platform.handle_inspection_input(button(MOUSE_BUTTON_WHEEL_UP))
		check(is_equal_approx(platform._orbit_zoom, platform.ORBIT_MIN_ZOOM), "Wheel up exceeded minimum zoom bound")
		var zoomed_size: float = platform.camera.size
		platform.handle_inspection_input(button(MOUSE_BUTTON_WHEEL_UP, false))
		check(platform.camera.size == zoomed_size, "Wheel release incorrectly zoomed twice")
		for _step in 100:
			platform.handle_inspection_input(button(MOUSE_BUTTON_WHEEL_DOWN))
		check(is_equal_approx(platform._orbit_zoom, platform.ORBIT_MAX_ZOOM), "Wheel down exceeded maximum zoom bound")
		check(platform.camera.size > 0.0 and is_finite(platform.camera.size), "Zoom produced an invalid orthographic size")
		check(snapshot(other) == untouched and not other.is_inspecting(), "One instance changed another instance's camera")
		check(platform.shape.polygon == polygon, "Inspection changed the gameplay collision polygon")
		platform.exit_inspection()
		platform.exit_inspection()
		check_restored(platform, original)
		for shadow in shadows:
			check(shadow.visible == shadow_visible, "Exit did not preserve the ambient shadow's prior visibility")
		check(node_count(platform) == original_nodes, "Inspection enter/exit leaked scene nodes")
	platform.enter_inspection()
	other.enter_inspection()
	var other_orbit := snapshot(other)
	platform.handle_inspection_input(button(MOUSE_BUTTON_WHEEL_UP))
	check(snapshot(other) == other_orbit, "Two active inspection cameras share zoom state")
	other.exit_inspection()
	check_restored(other, untouched)
	# Inspection must not perturb the normal state/animation lifecycle.
	platform.activate()
	other.activate()
	for _tick in 340:
		platform.advance(0.01)
		other.advance(0.01)
		check(platform.state == other.state and platform._animation_index == other._animation_index, "Orbit input altered lifecycle state")
		check(platform.elapsed == other.elapsed and platform._animation_time == other._animation_time, "Orbit input altered lifecycle clocks")
	platform.reset()
	check_restored(platform, original)
	check(platform.state == platform.State.READY and platform._animation_index == 0, "Reset failed after inspection")
	other.exit_inspection()
	check_restored(other, untouched)
	platform.enter_inspection()
	var camera_ref: WeakRef = weakref(platform.camera)
	var viewport_ref: WeakRef = weakref(platform.viewport)
	var model_ref: WeakRef = weakref(platform.model)
	platform.queue_free()
	other.queue_free()
	await frames(2)
	check(camera_ref.get_ref() == null and viewport_ref.get_ref() == null and model_ref.get_ref() == null, "Teardown leaked inspection scene nodes")


func check_preview_input() -> void:
	var preview: Node2D = Preview.instantiate()
	root.add_child(preview)
	preview.device.settings = preview.device.settings.duplicate()
	preview.device.settings.sound_enabled = false
	var sink := InputSink.new()
	root.add_child(sink)
	var original := snapshot(preview.device)
	root.push_input(key(KEY_V))
	check(preview.inspecting and preview.device.is_inspecting(), "Preview V did not enter orbit")
	root.push_input(key(KEY_V, true, true))
	check(preview.inspecting, "Repeated V key echo toggled the view")
	root.push_input(key(KEY_SPACE))
	root.push_input(key(KEY_J))
	root.push_input(button(MOUSE_BUTTON_LEFT))
	var before: Transform3D = preview.device.camera.transform
	root.push_input(motion(Vector2(30, 20)))
	root.push_input(button(MOUSE_BUTTON_WHEEL_UP))
	check(preview.device.camera.transform != before and preview.device._orbit_zoom < 1.0, "Preview does not route drag and wheel input")
	check(preview.device.state == preview.device.State.READY, "Preview inspection Space activated gameplay")
	check(sink.received == 0, "Preview inspection input leaked to unhandled gameplay callbacks")
	root.push_input(key(KEY_V))
	check_restored(preview.device, original)
	root.push_input(key(KEY_SPACE))
	check(preview.device.state == preview.device.State.COUNTDOWN, "Preview gameplay controls were not restored")
	root.push_input(key(KEY_V))
	root.push_input(key(KEY_R))
	check(not preview.inspecting and preview.device.state == preview.device.State.READY, "Preview R did not reset and leave inspection")
	check_restored(preview.device, original)
	root.push_input(key(KEY_V))
	var device_ref: WeakRef = weakref(preview.device)
	preview.queue_free()
	sink.queue_free()
	await frames(2)
	check(device_ref.get_ref() == null, "Preview teardown retained its inspected device")


func check_workshop_input() -> void:
	var path: String = Platform.resource_path.get_base_dir().get_base_dir().get_base_dir() + "/Examples/DisappearingPlatform3DWorkshop.tscn"
	if not ResourceLoader.exists(path):
		print("WORKSHOP_ORBIT_SKIPPED (standalone device copy; preview input checks remain active)")
		return
	var scene: PackedScene = load(path)
	var workshop: Node2D = scene.instantiate()
	root.add_child(workshop)
	var actor: CharacterBody2D = workshop.player
	actor.process_mode = Node.PROCESS_MODE_ALWAYS
	actor.position = Vector2(200, 100)
	actor.velocity = Vector2(40, 75)
	actor.left = true
	actor.right = true
	actor.pending_jump = true
	actor.pending_attack = true
	actor.attack_remaining = 0.2
	var position_before := actor.position
	var velocity_before := actor.velocity
	var modes_before := [actor.process_mode, actor.is_processing(), actor.is_physics_processing(), actor.is_processing_unhandled_key_input()]
	var original: Array[Dictionary] = []
	for platform: Node in workshop.platforms:
		platform.settings = platform.settings.duplicate()
		platform.settings.sound_enabled = false
		original.append(snapshot(platform))
	var sink := InputSink.new()
	root.add_child(sink)
	for cycle in 5:
		root.push_input(key(KEY_V))
		check(workshop.inspecting and actor.process_mode == Node.PROCESS_MODE_DISABLED, "Workshop V failed to freeze actor")
		check(not actor.left and not actor.right and not actor.pending_jump and not actor.pending_attack and actor.attack_remaining == 0.0, "Inspection entry did not clear all transient actor inputs")
		for code: Key in [KEY_A, KEY_D, KEY_SPACE, KEY_J, KEY_K]:
			root.push_input(key(code))
			root.push_input(key(code, false))
		root.push_input(button(MOUSE_BUTTON_LEFT))
		root.push_input(motion(Vector2(50, -20)))
		root.push_input(button(MOUSE_BUTTON_WHEEL_DOWN))
		var device: Node2D = workshop.platforms[0]
		device.activate()
		var elapsed_before: float = device.elapsed
		await frames(4)
		check(actor.position == position_before and actor.velocity == velocity_before, "Actor moved or fell while inspecting")
		check(not actor.left and not actor.right and not actor.pending_jump and not actor.pending_attack and actor.attack_remaining == 0.0, "Inspection controls triggered actor movement or attack")
		check(device.elapsed > elapsed_before, "Freezing actor also paused the device lifecycle")
		check(sink.received == 0, "Workshop inspection events leaked to unhandled gameplay callbacks")
		for platform: Node in workshop.platforms:
			check(platform.is_inspecting() and platform._orbit_zoom > 1.0, "Workshop did not route inspection to all platform cameras")
		root.push_input(key(KEY_V))
		check(not workshop.inspecting, "Second V did not exit workshop inspection")
		check([actor.process_mode, actor.is_processing(), actor.is_physics_processing(), actor.is_processing_unhandled_key_input()] == modes_before, "Actor processing flags were not preserved exactly")
		for index in workshop.platforms.size():
			check_restored(workshop.platforms[index], original[index])
	# Ensure normal movement can resume only on a fresh input after leaving.
	root.push_input(key(KEY_D))
	check(actor.right, "Gameplay actor input was not restored on exit")
	root.push_input(key(KEY_D, false))
	root.push_input(key(KEY_V))
	root.push_input(key(KEY_R))
	check(not workshop.inspecting and actor.process_mode == modes_before[0], "Workshop reset left the actor disabled")
	check(actor.position == Vector2(120, 500) and actor.velocity == Vector2.ZERO, "Workshop reset failed while inspecting")
	for index in workshop.platforms.size():
		check_restored(workshop.platforms[index], original[index])
		check(workshop.platforms[index].state == 0, "Workshop reset did not reset platform state")
	# A host-disabled actor must stay disabled after inspection, too.
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.push_input(key(KEY_V))
	root.push_input(key(KEY_V))
	check(actor.process_mode == Node.PROCESS_MODE_DISABLED, "Inspection exit enabled a previously disabled actor")
	root.push_input(key(KEY_V))
	var actor_ref: WeakRef = weakref(actor)
	workshop.queue_free()
	sink.queue_free()
	await frames(2)
	check(actor_ref.get_ref() == null, "Workshop teardown retained its frozen actor")
