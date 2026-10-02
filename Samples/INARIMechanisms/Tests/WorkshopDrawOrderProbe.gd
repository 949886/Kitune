extends SceneTree
## Exercise every gallery entry and its standalone scene. Graph checks run
## headless; graphical runs also verify the body pixels over real devices.
const Gallery = preload("../Examples/DeviceGallery.tscn")
const DeviceSprite = preload("../Core/DeviceSprite.gd")
var checked_players := 0
var rendered_players := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	create_timer(60, true, false, true).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	var exhibits: Array = gallery.EXHIBITS
	for index in gallery.EXHIBITS.size():
		gallery.select_exhibit(index)
		await frames(3)
		var exhibit: Node = gallery.exhibit
		check_scene(exhibit)
		# These hosts keep their player alive while rebuilding device trees.
		if exhibit.has_method("reset_doors"):
			exhibit.reset_doors()
		elif exhibit.has_method("_reload"):
			exhibit._reload()
		elif exhibit.has_method("_install"):
			for destination: PackedScene in exhibit.destinations.values():
				exhibit._install(destination)
				await frames(2)
				check_scene(exhibit)
			exhibit._install(exhibit.initial_scene)
		await frames(2)
		check_scene(exhibit)
		if DisplayServer.get_name() != "headless" and exhibit.name in [&"DoorWorkshop", &"ElevatorWorkshop"]:
			await check_rendered_body(exhibit)
	gallery.queue_free()
	await frames(2)
	# F6 must use exactly the same policy without the gallery host.
	for scene: PackedScene in exhibits:
		var exhibit := scene.instantiate()
		# A host-authored parent Z must participate in the final order too.
		exhibit.z_index = 37
		root.add_child(exhibit)
		await frames(3)
		check_scene(exhibit)
		exhibit.queue_free()
		await frames(2)
	if failures == 0:
		print("WORKSHOP_DRAW_ORDER_PROBE_PASS players=%d rendered=%d" % [checked_players, rendered_players])
	quit(int(failures > 0))


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func check_scene(exhibit: Node) -> void:
	var player := exhibit.get_node_or_null("Player") as CharacterBody2D
	if player == null:
		return
	for visual: Node in exhibit.find_children("*", "Sprite2D", true, false):
		if player.is_ancestor_of(visual) or visual.get_canvas() != player.get_canvas():
			continue
		check(
			draw_z(player) > draw_z(visual),
			"Player is obscured in %s by %s" % [exhibit.name, visual.get_path()]
		)
	checked_players += 1
	# Repeated updates must not make the checkpoint's second actor compete
	# with the player for increasingly high Z values.
	var previous_z: int = player.z_index
	player._refresh_draw_order()
	check(player.z_index == previous_z, "Repeated draw-order refresh must be stable")


func draw_z(item: CanvasItem) -> int:
	var result: int = item.z_index
	if item.z_as_relative and not item.top_level and item.get_parent() is CanvasItem:
		result += draw_z(item.get_parent())
	return result


func check_rendered_body(exhibit: Node) -> void:
	var player: CharacterBody2D = exhibit.get_node("Player")
	player.set_physics_process(false)
	# Put the body over an actual authored sprite, then let the host's camera
	# follow. This catches a simulated actor that is still hidden on screen.
	for sprite: Node in exhibit.find_children("*", "Sprite2D", true, false):
		if sprite is not DeviceSprite or not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		player.global_position = sprite.to_global(sprite.get_rect().get_center()) + Vector2(0, 16)
		await frames(2)
		var point := Vector2i(player.get_global_transform_with_canvas() * Vector2(0, -16))
		if not Rect2i(Vector2i.ZERO, root.size).has_point(point):
			continue
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var color := picture.get_pixelv(point)
		var expected := Color("9dd9e5")
		check(
			absf(color.r - expected.r) < 0.03
			and absf(color.g - expected.g) < 0.03
			and absf(color.b - expected.b) < 0.03,
			"Player body is hidden on screen in %s: %s" % [exhibit.name, color]
		)
		rendered_players += 1
		if not OS.get_environment("INARI_CAPTURE").is_empty():
			var folder := OS.get_environment("INARI_CAPTURE")
			picture.save_png(folder.path_join(str(exhibit.name) + ".png"))
		return
	check(false, "No on-screen device available for the rendering check")
