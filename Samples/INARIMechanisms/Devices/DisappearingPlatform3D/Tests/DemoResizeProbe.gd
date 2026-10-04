extends SceneTree
## Headless layout/input assertions, not a rendered screenshot comparison.
## Runs from either the repository or a renamed, nested device-only copy.
const Preview = preload("../Examples/Preview.tscn")
const SIZES: Array[Vector2i] = [
	Vector2i(1024, 720), Vector2i(1920, 1080), Vector2i(1478, 831),
	Vector2i(800, 1200), Vector2i(320, 240), Vector2i(2560, 720),
	Vector2i(240, 640), Vector2i(160, 120), Vector2i(1024, 576),
]
var checks := 0
var failed := false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func frames(count := 2) -> void:
	for _frame in count:
		await process_frame


func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func button(index: MouseButton, position: Vector2, pressed := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.factor = 1.0
	event.position = position
	return event


func run() -> void:
	var original_clear := RenderingServer.get_default_clear_color()
	await check_window(Preview, Vector2(1024, 720), false)
	await check_scene(Preview, Vector2(1024, 720), false)
	var workshop_path := Preview.resource_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir() + "/Examples/DisappearingPlatform3DWorkshop.tscn"
	if ResourceLoader.exists(workshop_path):
		await check_window(load(workshop_path), Vector2(1024, 576), true)
		await check_scene(load(workshop_path), Vector2(1024, 576), true)
	else:
		print("WORKSHOP_RESIZE_SKIPPED (standalone device copy)")
	check(RenderingServer.get_default_clear_color() == original_clear, "Demo changed the global clear color")
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_DEMO_RESIZE_PASS checks=", checks)
	quit(1 if failed else 0)


func check_window(scene: PackedScene, design_size: Vector2, is_workshop: bool) -> void:
	var original_size := root.size
	var demo: Node2D = scene.instantiate()
	root.add_child(demo)
	if is_workshop:
		demo.player.process_mode = Node.PROCESS_MODE_DISABLED
	# Exercise the root Window path used by F6 as well as an embedded viewport.
	for size: Vector2i in SIZES:
		root.size = size
		await frames()
		check(root.get_visible_rect().size.is_equal_approx(Vector2(size)), "Root Window did not expose the resized content dimensions")
		check_layout(demo, Vector2(size), design_size)
	demo.queue_free()
	await frames()
	root.size = original_size
	await frames()


func check_scene(scene: PackedScene, design_size: Vector2, is_workshop: bool) -> void:
	var host := SubViewport.new()
	host.size = SIZES[0]
	host.own_world_3d = true
	root.add_child(host)
	var demo: Node2D = scene.instantiate()
	host.add_child(demo)
	var devices: Array[Node] = []
	if is_workshop:
		devices.assign(demo.platforms)
	else:
		devices.append(demo.device)
	var world_transforms: Array[Transform2D] = []
	var camera_transforms: Array[Transform3D] = []
	for device: Node2D in devices:
		device.settings = device.settings.duplicate()
		device.settings.sound_enabled = false
		device.set_physics_process(false)
		world_transforms.append(device.global_transform)
		camera_transforms.append(device.camera.transform)
	if is_workshop:
		demo.player.process_mode = Node.PROCESS_MODE_DISABLED
	var layout: Node = demo.demo_layout
	var first_count := demo.get_child_count()
	await frames()
	# Changing the real host viewport exercises its size_changed signal. Repeat
	# the full sequence so resize cannot compound zoom, transforms or UI scale.
	for cycle in 3:
		for size: Vector2i in SIZES:
			host.size = size
			await frames()
			check_layout(demo, Vector2(size), design_size)
			var world_to_screen := demo.get_global_transform_with_canvas()
			for index in devices.size():
				var device: Node2D = devices[index]
				check(device.global_transform == world_transforms[index], "Resize moved/scaled gameplay or collision geometry")
				check(device.camera.transform == camera_transforms[index], "Resize changed a device's gameplay camera")
				var screen_point := world_to_screen * device.position
				var local_point: Vector2 = device.get_global_transform_with_canvas().affine_inverse() * screen_point
				check(local_point.is_equal_approx(Vector2.ZERO), "Screen/world input coordinates no longer align with device origin")
			var anchor: Vector2 = world_to_screen * devices[0].position
			host.push_input(key(KEY_V), true)
			check(demo.inspecting, "V did not enter inspection after resize")
			await frames()
			check_hud(demo.label, Vector2(size))
			host.push_input(button(MOUSE_BUTTON_LEFT, anchor), true)
			var motion := InputEventMouseMotion.new()
			motion.position = anchor + Vector2(18, -12)
			motion.relative = Vector2(18, -12)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			host.push_input(motion, true)
			host.push_input(button(MOUSE_BUTTON_WHEEL_UP, anchor), true)
			for device: Node2D in devices:
				check(is_equal_approx(device._orbit_yaw, deg_to_rad(35.0) - 18.0 * device.ORBIT_SENSITIVITY), "Resize scaled or offset horizontal orbit input")
				check(is_equal_approx(device._orbit_pitch, deg_to_rad(20.0) - 12.0 * device.ORBIT_SENSITIVITY), "Resize scaled or offset vertical orbit input")
				check(is_equal_approx(device._orbit_zoom, 1.0 / 1.12), "Wheel input changed with viewport dimensions")
			# Resize during an active drag, then release in the resized viewport.
			host.size = Vector2i(size.y, size.x)
			await frames()
			check_layout(demo, Vector2(host.size), design_size)
			host.push_input(button(MOUSE_BUTTON_LEFT, Vector2(host.size) * 0.5, false), true)
			var yaw_before: float = devices[0]._orbit_yaw
			host.push_input(motion, true)
			check(is_equal_approx(devices[0]._orbit_yaw, yaw_before), "Mouse release after resize left stale orbit drag")
			host.push_input(key(KEY_R if cycle % 2 == 0 else KEY_V), true)
			check(not demo.inspecting, "V/R failed to leave inspection after resize")
			for index in devices.size():
				check(devices[index].camera.transform == camera_transforms[index], "Inspection exit did not restore gameplay camera after resize")
			check(demo.get_child_count() == first_count, "Repeated resize leaked demo nodes")
	var layout_ref: WeakRef = weakref(layout)
	var camera_ref: WeakRef = weakref(layout.camera)
	var background_ref: WeakRef = weakref(layout.background)
	host.queue_free()
	await frames()
	check(layout_ref.get_ref() == null and camera_ref.get_ref() == null and background_ref.get_ref() == null, "Demo teardown retained resize presentation nodes")


func check_layout(demo: Node2D, viewport_size: Vector2, design_size: Vector2) -> void:
	var layout: Node = demo.demo_layout
	var fit := minf(viewport_size.x / design_size.x, viewport_size.y / design_size.y)
	check(layout.camera.zoom.is_equal_approx(Vector2.ONE * fit), "Scene does not uniformly fit both viewport dimensions")
	var transform := demo.get_global_transform_with_canvas()
	check((transform * (design_size * 0.5)).is_equal_approx(viewport_size * 0.5), "Scene center drifted after resize")
	var stage_rect := transform * Rect2(Vector2.ZERO, design_size)
	check(Rect2(Vector2.ZERO, viewport_size).grow(0.01).encloses(stage_rect), "Resize cropped the authored scene")
	check(is_equal_approx(transform.x.length(), transform.y.length()), "Scene aspect ratio was distorted")
	var background: ColorRect = layout.background
	var background_rect := background.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, background.size)
	check(background_rect.position.is_equal_approx(Vector2.ZERO) and background_rect.size.is_equal_approx(viewport_size), "Background leaves uncovered viewport edges")
	check(background.color.a == 1.0 and background.get_parent().layer < 0, "Background is not opaque behind the scene")
	check(background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Background intercepts demo input")
	check_hud(demo.label, viewport_size)


func check_hud(label: Label, viewport_size: Vector2) -> void:
	var hud_rect := label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
	check(Rect2(Vector2.ZERO, viewport_size).grow(0.01).encloses(hud_rect), "HUD overflowed the viewport")
	check(hud_rect.position.x > 0.0 and hud_rect.position.y > 0.0, "HUD lost its screen-space margins")
	check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD intercepts orbit input")
