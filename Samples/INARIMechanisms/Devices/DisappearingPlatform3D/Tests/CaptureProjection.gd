extends SceneTree
## Real-engine visual regression capture; requires a rendering display driver.
const Platform = preload("../DisappearingPlatform3D.tscn")
var reference: Node2D

func _initialize() -> void:
	call_deferred("run")

func capture(device: Node, name: String, folder: String) -> void:
	device.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
	assert(result == OK)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Real projection capture needs X11/Wayland/native display; headless is a dummy renderer.")
		quit(2)
		return
	root.size = Vector2i(1024, 720)
	var background := ColorRect.new()
	background.size = Vector2(1024,720)
	background.color = Color("23383e")
	root.add_child(background)
	var device := Platform.instantiate()
	var legacy_path: String = get_script().resource_path.get_base_dir().get_base_dir().get_base_dir().path_join("DisappearingPlatform/DisappearingPlatform.tscn")
	if ResourceLoader.exists(legacy_path):
		reference = load(legacy_path).instantiate()
		reference.position = Vector2(256,330)
		reference.scale = Vector2(3,3)
		root.add_child(reference)
		reference.set_physics_process(false)
		var label := Label.new()
		label.text = "Godot capture: original 2D (left) / solid 3D (right), same 3x scale"
		label.position = Vector2(24,24)
		root.add_child(label)
	device.position = Vector2(768 if reference != null else 512,330)
	device.scale = Vector2(3,3)
	root.add_child(device)
	device.set_physics_process(false)
	var folder := OS.get_environment("INARI_3D_CAPTURE_DIR")
	if folder.is_empty():
		folder = OS.get_user_data_dir().path_join("platform3d-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	await capture(device,"ready",folder)
	device.activate()
	if reference != null: reference.activate()
	device.advance(0.22)
	if reference != null: reference.advance(0.22)
	await capture(device,"alarm",folder)
	device.advance(1.6)
	if reference != null: reference.advance(1.6)
	await capture(device,"folding",folder)
	device.advance(0.3)
	if reference != null: reference.advance(0.3)
	await capture(device,"hidden",folder)
	device.advance(0.95)
	if reference != null: reference.advance(0.95)
	device.advance(0.16)
	if reference != null: reference.advance(0.16)
	await capture(device,"recovering",folder)
	device.reset()
	if reference != null: reference.reset()
	device.set_inspection_angle(35)
	await capture(device,"angled-geometry",folder)
	print("PLATFORM_3D_CAPTURE_PASS: ",folder)
	quit()
