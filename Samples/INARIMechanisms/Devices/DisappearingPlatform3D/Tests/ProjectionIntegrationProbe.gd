extends SceneTree
## The generic shell may rebuild without restarting platform gameplay or orbit.
const Platform = preload("../DisappearingPlatform3D.tscn")
const Preview = preload("../Examples/Preview.tscn")
var checks := 0
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)

func snapshot(device: Node2D) -> Array:
	return [device.state, device.elapsed, device._animation_index, device._animation_time,
		device._pending_active, device._recover_blend, device.shape.disabled]

func create_device() -> Node2D:
	var device: Node2D = Platform.instantiate()
	device.settings = device.settings.duplicate()
	device.settings.sound_enabled = false
	root.add_child(device)
	device.set_physics_process(false)
	return device

func run() -> void:
	var device := create_device()
	var other := create_device()
	var collider: Node = device.solid
	var shape: Node = device.shape
	var sound: Node = device.audio
	check(device.mechanism.global_position.is_equal_approx(Vector3(-2.1338387, -5.0161667, 0)), "Projection changed assembly world placement")
	check(device.activate(), "Activation failed")
	device.advance(1.82)
	await process_frame
	device.enter_inspection()
	device._orbit_yaw = 0.75
	device._orbit_pitch = 0.3
	device._orbit_zoom = 0.8
	device._update_inspection_camera()
	var state := snapshot(device)
	var pose: Basis = device.mechanism.hinge.basis
	var alpha: float = device.mechanism.alarm.modulate.a
	var neighbor: Array = snapshot(other)
	for iteration in 6:
		var old_model: WeakRef = weakref(device.mechanism)
		var old_view: WeakRef = weakref(device.viewport)
		check(device.projection.rebuild(), "Generic rebuild failed")
		device.set_physics_process(false)
		check(old_model.get_ref() == null and old_view.get_ref() == null, "Rebuild retained obsolete model or viewport")
		check(device.solid == collider and device.shape == shape and device.audio == sound, "Rebuild replaced business nodes")
		check(snapshot(device) == state, "Rebuild restarted platform clock/state/collision")
		check(device.mechanism.hinge.basis.is_equal_approx(pose), "Rebuild changed active hinge pose")
		check(is_equal_approx(device.mechanism.alarm.modulate.a, alpha), "Rebuild changed alarm alpha")
		check(device.is_inspecting() and device.mechanism.inspection_materials, "Rebuild left inspection")
		check(is_equal_approx(device._orbit_yaw, 0.75) and is_equal_approx(device._orbit_pitch, 0.3) and is_equal_approx(device._orbit_zoom, 0.8), "Rebuild reset orbit coordinates")
		check(snapshot(other) == neighbor and not other.is_inspecting(), "Rebuild changed another instance")
		check(device.projection.get_child_count() == 0 and device.projection.get_child_count(true) == 2, "Projection leaked visible or duplicate generated roots")
	var original_scene: PackedScene = device.projection.scene
	var invalid_scene := PackedScene.new()
	var wrong_root := Node2D.new()
	check(invalid_scene.pack(wrong_root) == OK, "Could not build invalid-scene fixture")
	wrong_root.free()
	device.projection.scene = invalid_scene
	check(not device.projection.ensure_built(), "Non-3D replacement unexpectedly succeeded")
	check(not device._projection_ready and not device.is_physics_processing(), "Invalid replacement left platform processing stale content")
	check(not device.activate(), "Invalid replacement accepted activation")
	device.advance(3.0)
	check(snapshot(device) == state, "Invalid replacement advanced platform gameplay")
	check(device.handle_inspection_input(InputEventMouseMotion.new()), "Invalid replacement leaked inspection input")
	device.projection.scene = original_scene
	check(device.projection.ensure_built(), "Repairing injected scene failed")
	device.set_physics_process(false)
	check(snapshot(device) == state and device.is_inspecting(), "Repair lost platform or inspection state")
	device.exit_inspection()
	check(device.camera.position.is_equal_approx(device.projection.camera_position), "Orbit did not restore rebuilt base camera")
	check(is_equal_approx(device.camera.size, device.projection.camera_size), "Orbit did not restore rebuilt base size")
	check(device.display.position.is_equal_approx(device.projection.sprite_position), "Orbit did not restore rebuilt display")
	var scene: PackedScene = device.projection.scene
	device.projection.scene = scene.duplicate()
	check(device.projection.ensure_built(), "Replacing injected scene failed")
	device.set_physics_process(false)
	check(snapshot(device) == state and device.mechanism.hinge.basis.is_equal_approx(pose), "Scene replacement lost active state")
	device.advance(1.25)
	await process_frame
	state = snapshot(device)
	check(device.projection.rebuild(), "Recovery rebuild failed")
	device.set_physics_process(false)
	check(snapshot(device) == state, "Recovery rebuild lost collision/timing state")
	device.reset()
	await process_frame
	check(device.state == device.State.READY and not device.shape.disabled and not device.is_inspecting(), "R/reset failed after rebuilds")
	root.remove_child(device)
	root.add_child(device)
	check(device.projection.ensure_built(), "Detach/reattach broke projection")
	check(device.solid == collider and device.mechanism != null, "Detach/reattach replaced business nodes")
	var preview: Node2D = Preview.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	preview.device.set_physics_process(false)
	preview.device.projection.scene = invalid_scene
	check(not preview.device.projection.ensure_built(), "Preview accepted invalid 3D content")
	preview._process(0.0)
	check(preview.label.text.contains("content unavailable"), "Preview did not report unavailable content safely")
	preview.device.reset()
	preview.device.projection.scene = original_scene
	check(preview.device.projection.ensure_built(), "Preview could not recover injected content")
	preview.device.set_physics_process(false)
	preview._process(0.0)
	check(not preview.label.text.contains("content unavailable"), "Preview HUD did not recover with content")
	preview.free()
	device.free()
	other.free()
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_PROJECTION_INTEGRATION_PASS checks=", checks)
	quit(1 if failed else 0)
