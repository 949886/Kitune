extends SceneTree

const Stage = preload("res://Samples/ArtDirection/Runtime/OriginalStage.gd")
const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var stage := Stage.new()
	root.add_child(stage)
	var number := "2"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			number = arg.trim_prefix("level=")
	stage.configure("res://Samples/ArtDirection/Original/INARI/level%s.json" % number)
	if number == "2":
		stage.spawn = Vector2(-9207.05, 6381.12)
	if number == "25":
		stage.spawn = Vector2(0, -140)
	var player := Player.new()
	root.add_child(player)
	player.position = stage.spawn
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.checkpoint = stage.spawn
	player.z_index = stage.sort_depth(player.tuning.sprite_sort)
	var framing := {"camera_fixed": [stage.spawn.x + 180, stage.spawn.y - 60], "zoom": 1.0}
	if number == "25":
		framing.camera_fixed = [0, -300]
		framing.zoom = 0.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("camera="):
			var parts := arg.trim_prefix("camera=").split(",")
			framing.camera_fixed = [float(parts[0]), float(parts[1])]
		if arg.begins_with("zoom="):
			framing.zoom = float(arg.trim_prefix("zoom="))
	# Fixed diagnostic framing remains adjustable through camera= and zoom=.
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = Assets.vec(framing.camera_fixed)
	camera.zoom = Vector2.ONE * float(framing.zoom)
	camera.force_update_scroll()
	stage.projection.attach_camera(camera)
	for frame in range(3):
		await physics_frame
	player.process_mode = Node.PROCESS_MODE_INHERIT
	print(
		"RAY ",
		root.world_2d.direct_space_state.intersect_ray(
			PhysicsRayQueryParameters2D.create(stage.spawn, stage.spawn + Vector2(0, 100), 1)
		)
	)
	for node in stage.get_children():
		if node is StaticBody2D and node.position.distance_to(stage.spawn) < 100:
			print(
				"BODY ",
				node.position,
				" ",
				node.get_child_count(),
				" ",
				node.get_child(0).position,
				" ",
				node.collision_layer
			)
	for frame in range(60):
		await physics_frame
		if frame < 12:
			print(
				"STEP ",
				frame,
				" ",
				player.position,
				" ",
				player.velocity,
				" hit=",
				player.get_slide_collision_count()
			)
			for i in player.get_slide_collision_count():
				print(player.get_slide_collision(i).get_collider().name)
	print(
		"PROBE player=",
		player.position,
		" spawn=",
		stage.spawn,
		" floor=",
		player.is_on_floor(),
		" solids=",
		stage.solid_count
	)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		assert(Capture.save_png(root, "res://tmp/art-direction/inari_%s.png" % number) == OK)
	quit()
