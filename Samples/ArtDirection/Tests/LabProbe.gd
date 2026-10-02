extends SceneTree
## Integration probe: real viewports, collisions, scene changes and reference UI.

const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	assert(lab.profiles.size() == 3)
	assert(lab.profiles[0].id == "inari_factory")
	assert(lab.profiles[1].id == "inari_seal")
	assert(lab.profiles[2].id == "inari_machinery")
	# Stale numeric shortcuts and indices must leave the gallery intact.
	for key in [KEY_1 + lab.profiles.size(), KEY_6]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		lab._unhandled_key_input(event)
	lab.load_level(-1)
	lab.load_level(lab.profiles.size())
	assert(lab.selected == -1 and lab.gallery.visible)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/gallery.png")
	for index in lab.profiles.size():
		lab.load_level(index)
		for frame in range(60):
			await physics_frame
		_verify_original_stage(lab)
		print(
			"LEVEL ",
			lab.profiles[index].id,
			" floor=",
			lab.player.is_on_floor(),
			" position=",
			lab.player.position
		)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://tmp/art-direction/" + str(lab.profiles[index].id) + ".png"
			)
		# Exercise an actual movement input through the player controller.
		var start: Vector2 = lab.player.position
		var right: StringName = lab.player.input_action("right")
		Input.action_press(right)
		for frame in range(20):
			await physics_frame
		Input.action_release(right)
		print("MOVED ", lab.player.position.distance_to(start))
		assert(lab.player.position.distance_to(start) > 1.0, "Controller did not move")
		assert(lab.player.get_script().resource_path.ends_with("InariStudyPlayer.gd"))
		lab.respawn_player()
		assert(lab.player.position == lab.get_checkpoint())
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		lab._unhandled_key_input(tab)
		assert(lab.reference_mode == lab.profiles[index].has("reference"))
		assert(lab.reference_view.visible == lab.profiles[index].has("reference"))
		lab._unhandled_key_input(tab)
		assert(not lab.reference_mode and lab.controls_enabled)
		lab.show_gallery()
		assert(lab.gallery.visible and not lab.controls_enabled)
	print("LAB_PROBE_PASS")
	lab.queue_free()
	await process_frame
	quit()


func _verify_original_stage(lab: Node) -> void:
	assert(lab.camera_rig.get_script().resource_path.ends_with("InariCameraRig.gd"))
	var profile: Dictionary = lab.profiles[lab.selected]
	var expected_size: Vector2i
	if profile.has("reference"):
		var reference: Texture2D = load(lab.REFERENCE_ROOT + profile.reference)
		expected_size = Vector2i(reference.get_size())
	else:
		expected_size = Vector2i(Assets.vec(profile.viewport_size))
	assert(lab.viewport.size == expected_size, "Scene must retain native detail")
	# More raster pixels must not zoom the world or alter the source camera's framing.
	var source: Dictionary = lab.stage.source_camera
	var height: float = (
		2.0 * lab.camera_rig.camera_distance * tan(deg_to_rad(source.lens.FieldOfView) * 0.5)
	)
	height *= lab.player.tuning.pixels_per_unit
	assert(is_equal_approx(lab.viewport.size.y / lab.camera.zoom.y, height))
	# A native camera region changes world Z, while Cinemachine's XY guides
	# remain measured at m_CameraDistance from the tracked target.
	var guide_height: float = (
		2.0 * source.distance * tan(deg_to_rad(source.lens.FieldOfView) * 0.5) * lab.player.units
	)
	assert(is_equal_approx(lab.camera_rig.guide_size.y, guide_height))
	var ratio := float(profile.get("letterbox_ratio", 0.0))
	if is_instance_valid(lab.bloom):
		assert(is_equal_approx(lab.bloom.presentation.get_shader_parameter("letterbox"), ratio))
	elif ratio > 0.0:
		var bars: Node = lab.viewport.get_node("Letterbox")
		assert(bars.get_child_count() == 2)
		var top: ColorRect = bars.get_child(0)
		var bottom: ColorRect = bars.get_child(1)
		assert(top.size.is_equal_approx(Vector2(lab.viewport.size.x, lab.viewport.size.y * ratio)))
		assert(bottom.position.y + bottom.size.y == lab.viewport.size.y)
	assert(lab.viewport.use_hdr_2d == lab.stage.lighting.linear_framebuffer)
	if lab.viewport.use_hdr_2d and not root.use_hdr_2d:
		assert(lab.game_view.material != null, "Linear HDR game texture needs sRGB presentation")

	for node: Node in lab.stage.visuals_by_go.values():
		if node.get("is_water") and node.data.spatial.get("follow_camera_x", false):
			assert(absf(node.global_position.x - lab.camera.position.x) < 0.01)
			var surface: Vector2 = node.global_transform * node.destination.position
			assert(
				absf(surface.y - (-68.81528)) < 0.01,
				"Original water follower lost its source waterline"
			)

		if node.get_script() == Visual and not is_zero_approx(node.rotation_speed):
			if node.data.material == "Mat_TrapGeer":
				# The cog layer is in front of backgrounds despite a -500 order.
				assert(node.z_index > lab.stage.sort_depth([1, 10000]))
				assert(is_equal_approx(node.rotation_speed, deg_to_rad(500.0)))
			elif node.data.material == "Mat_BigFan":
				assert(is_equal_approx(node.rotation_speed, -deg_to_rad(100.0)))
			assert(
				node.elapsed > 0.0 and not is_equal_approx(node.rotation, node.original_rotation)
			)

	for node: Node in lab.stage.get_children():
		if node is CollisionObject2D:
			var source_layer: String = node.get_meta("source_layer", "")
			if source_layer == "Platform":
				assert((node.collision_layer & Collision.PROJECTILE_SURFACE) == 0)
				assert((node.collision_layer & Collision.ONE_WAY) != 0)
			elif source_layer == "Ground":
				assert((node.collision_layer & Collision.PROJECTILE_SURFACE) != 0)
