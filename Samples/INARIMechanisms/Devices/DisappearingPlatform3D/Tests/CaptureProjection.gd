extends SceneTree
## Real-engine visual regression capture; requires a rendering display driver.
const Platform = preload("../DisappearingPlatform3D.tscn")

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
	device.position = Vector2(512,330)
	device.scale = Vector2(3,3)
	root.add_child(device)
	device.set_physics_process(false)
	var folder := OS.get_environment("INARI_3D_CAPTURE_DIR")
	if folder.is_empty():
		folder = OS.get_user_data_dir().path_join("platform3d-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	await capture(device,"ready",folder)
	device.activate()
	device.advance(0.22)
	await capture(device,"alarm",folder)
	device.advance(1.6)
	await capture(device,"folding",folder)
	device.advance(0.3)
	await capture(device,"hidden",folder)
	device.advance(0.95)
	device.advance(0.16)
	await capture(device,"recovering",folder)
	device.reset()
	device.set_inspection_angle(35)
	await capture(device,"angled-geometry",folder)
	print("PLATFORM_3D_CAPTURE_PASS: ",folder)
	quit()
