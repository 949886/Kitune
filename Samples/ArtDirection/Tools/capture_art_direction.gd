extends SceneTree
## Capture the configured INARI entries with HUD hidden and native camera settling.
## Run with a GPU renderer; optional arguments: output=res://... and settle_frames=90.

const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Scene capture requires a GPU renderer")
		quit(1)
		return
	var directory := "res://tmp/art-direction/review"
	var settle_frames := 90
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			directory = argument.trim_prefix("output=")
		elif argument.begins_with("settle_frames="):
			settle_frames = maxi(1, argument.trim_prefix("settle_frames=").to_int())
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	root.size = Vector2i(1920, 1080)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	var records: Array[Dictionary] = []
	for index in lab.profiles.size():
		lab.load_level(index)
		lab.hud_visible = false
		lab.hud.hide()
		for frame in settle_frames:
			await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var profile: Dictionary = lab.profiles[index]
		var path: String = directory.path_join(profile.id + ".png")
		assert(Capture.save_png(root, path) == OK)
		(
			records
			. append(
				{
					"id": profile.id,
					"reference": profile.reference,
					"image": path,
					"fidelity": profile.fidelity,
					"player_position": [lab.player.position.x, lab.player.position.y],
					"camera": lab.camera_rig.get_script().resource_path,
					"scene_hdr": lab.viewport.use_hdr_2d,
				}
			)
		)
		print("CAPTURED ", profile.id)
	var manifest := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"png_color_space": "sRGB",
		"settle_frames": settle_frames,
		"levels": records,
	}
	var file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	print("ART_DIRECTION_CAPTURE_PASS")
	quit()
