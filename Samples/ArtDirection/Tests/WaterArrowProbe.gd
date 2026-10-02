extends SceneTree
## Arrow body/trail in the actual independent water target, without cloned logic.

const Mirror = preload("res://Samples/ArtDirection/Runtime/OriginalWaterProjectiles.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var capture: Node = lab.water_capture
	var mirror: Node = capture.projectiles
	var arrow: RigidBody2D = lab.stage.spawn_arrow(capture.camera.position, -0.3, 85.0, lab.player)
	arrow.freeze = true
	arrow.collision_mask = 0
	arrow.trail.set_process(false)
	var id := arrow.get_instance_id()
	assert(mirror.pairs.has(id), "Actual arrow spawn must notify the water view")
	var pair: Dictionary = mirror.pairs[id]
	assert(pair.sprite.get_script() == null and pair.trail.get_script() == null)
	assert(pair.sprite.get_viewport() == capture.viewport)
	assert(pair.trail.get_viewport() == capture.viewport)
	assert(pair.sprite.material != arrow.visual.material)
	assert(pair.trail.material != arrow.trail.material)
	assert(not pair.sprite.material.get_shader_parameter("linear_framebuffer"))
	assert(not pair.trail.material.get_shader_parameter("linear_framebuffer"))
	assert(pair.sprite.texture == arrow.visual.texture)
	assert(pair.trail.texture == arrow.trail.texture)
	assert(pair.trail.width_curve == arrow.trail.width_curve)
	assert(pair.trail.gradient == arrow.trail.gradient)
	assert(pair.trail.width == arrow.trail.width)
	assert(pair.sprite.z_index == arrow.visual.z_index)
	assert(pair.trail.z_index == arrow.trail.z_index)
	var main_linear = arrow.visual.material.get_shader_parameter("linear_framebuffer")
	for step in 3:
		arrow.position += Vector2(40, -15)
		arrow.trail.advance(1.0 / 60.0)
		mirror.sync()
		assert(pair.sprite.global_transform == arrow.visual.global_transform)
		assert(pair.trail.points == arrow.trail.points)
		assert(pair.trail.global_transform == arrow.trail.global_transform)
	assert(pair.trail.points.size() > 2)
	assert(arrow.visual.material.get_shader_parameter("linear_framebuffer") == main_linear)
	var sample_count: int = arrow.trail.samples.size()
	var source_clock: float = arrow.trail.clock
	for step in 5:
		mirror.sync()
	assert(arrow.trail.samples.size() == sample_count and arrow.trail.clock == source_clock)
	# Native Arrow ignores TimeManager; its reflection must still accept new poses.
	lab.stage.combat_clock.stop_frames(12, 1.0 / 60.0)
	arrow.position.x += 20
	arrow.trail.advance(1.0 / 60.0)
	mirror.sync()
	assert(pair.sprite.global_transform == arrow.visual.global_transform)
	assert(pair.trail.points == arrow.trail.points)
	var late := Mirror.new()
	capture.viewport.add_child(late)
	late.configure(lab.stage)
	assert(late.pairs.has(id), "Late water attachment must discover an in-flight arrow")
	late.queue_free()
	await process_frame
	arrow.hide()
	mirror.sync()
	assert(not pair.sprite.visible and not pair.trail.visible)
	arrow.show()
	mirror.sync()
	assert(pair.sprite.visible and pair.trail.visible)
	if DisplayServer.get_name() != "headless":
		await verify_gpu(lab, capture, pair)
	arrow.queue_free()
	mirror.sync()
	assert(mirror.pairs.is_empty())
	assert(not pair.sprite.visible and not pair.trail.visible)
	await process_frame
	var old: WeakRef = weakref(mirror)
	lab.load_level(0)
	await process_frame
	assert(old.get_ref() == null and lab.water_capture == null)
	lab.queue_free()
	await process_frame
	print("WATER_ARROW_PASS")
	quit()


func verify_gpu(lab: Node, capture: Node, pair: Dictionary) -> void:
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	for collection: Array in [
		capture.stage_pairs, capture.actor_pairs, capture.line_pairs, capture.marker_pairs
	]:
		for entry: Dictionary in collection:
			entry.copy.hide()
	capture.particles.hide()
	pair.trail.hide()
	await draw_frames()
	var body: Image = capture.viewport.get_texture().get_image()
	assert(covered_pixels(body) > 3, "Native arrow texture must render into the water target")
	pair.sprite.hide()
	pair.trail.show()
	await draw_frames()
	var trail: Image = capture.viewport.get_texture().get_image()
	assert(covered_pixels(trail) > 3, "Native trail texture must render into the water target")
	pair.trail.hide()
	await draw_frames()
	assert(capture.viewport.get_texture().get_image().get_used_rect().size == Vector2i.ZERO)
	pair.sprite.show()
	pair.trail.show()
	await draw_frames()
	capture.viewport.get_texture().get_image().save_png(
		"res://tmp/art-direction/inari_water_arrow.png"
	)
	print("WATER_ARROW_GPU body=", covered_pixels(body), " trail=", covered_pixels(trail))
	lab.process_mode = Node.PROCESS_MODE_INHERIT


func covered_pixels(image: Image) -> int:
	var count := 0
	var rect := image.get_used_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a > 0.01:
				count += 1
	return count


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
