extends SceneTree
## Native prefab sprite, root scale, sorting and radiance in both camera targets.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	var visual: Sprite2D = player.projectile
	var data: Dictionary = visual.renderer
	assert(data.sprite.name == "shuriken3 2" and data.sprite.ppu == 8.0)
	var pixels: Image = visual.texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pixels.get_data())
	assert(hash.finish().hex_encode() == data.sprite.pixel_sha256)
	assert(pixels.get_size() == Vector2i(47, 21))
	assert(visual.offset == Vector2(-23.5, -10.5) and not visual.centered)
	assert(not visual.z_as_relative and visual.z_index == lab.stage.sort_depth(data.sort))
	assert(visual.z_index < player.z_index, "Kunai retains its native Ground2 sorting")
	var material: ShaderMaterial = visual.material
	assert(material.shader.resource_path.ends_with("OriginalLit.gdshader"))
	assert(material.get_shader_parameter("glow_global") == 4.0)
	assert(material.get_shader_parameter("glow_affects_light"))
	assert(material.get_shader_parameter("lit_amount") == 0.0)
	var copy: Sprite2D = lab.water_capture.actor_pairs[1].copy
	assert(copy.material != material)
	assert(not copy.material.get_shader_parameter("linear_framebuffer"))
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2(0.6, -0.8)]:
		player.throw_projectile(direction)
		assert(visual.scale.is_equal_approx(Vector2(0.8, 0.8)))
		assert(Vector2.from_angle(visual.rotation).is_equal_approx(direction))
		assert(visual.global_position.is_equal_approx(player.position + player.body_shape.position))
		lab.water_capture._process(0.0)
		assert(copy.transform == visual.global_transform and copy.texture == visual.texture)
		assert(copy.offset == visual.offset and not copy.centered)
		assert(
			copy.z_index == visual.z_index,
			"Water must not add the player's sort to absolute kunai order"
		)
	material.set_shader_parameter("hit_blend", 0.4)
	visual.modulate.a = 0.3
	lab.water_capture._process(0.0)
	assert(is_equal_approx(copy.material.get_shader_parameter("hit_blend"), 0.4))
	assert(is_equal_approx(copy.modulate.a, 0.3))
	player.throw_projectile(Vector2.RIGHT)
	assert(material.get_shader_parameter("hit_blend") == 0.0 and visual.modulate.a == 1.0)
	if DisplayServer.get_name() != "headless":
		await verify_gpu(visual)
	player._clear_projectile()
	lab.water_capture._process(0.0)
	assert(not visual.visible and not copy.visible)
	lab.queue_free()
	await process_frame
	print("KUNAI_RENDERING_PASS")
	quit()


func verify_gpu(original: Sprite2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 64)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var visual := Sprite2D.new()
	visual.texture = original.texture
	visual.texture_filter = original.texture_filter
	visual.position = Vector2(48, 32)
	visual.scale = original.scale
	visual.material = original.material.duplicate()
	viewport.add_child(visual)
	var material: ShaderMaterial = visual.material
	material.set_shader_parameter("linear_framebuffer", viewport.use_hdr_2d)
	material.set_shader_parameter("light_count", 0)
	material.set_shader_parameter("ambient", Vector3.ONE)
	await draw_frames()
	var bright: Image = viewport.get_texture().get_image()
	material.set_shader_parameter("ambient", Vector3.ZERO)
	await draw_frames()
	var dark: Image = viewport.get_texture().get_image()
	# Source GLOWLIGHT_ON with LitAmount=0 preserves the entire emitted surface.
	assert(bright.get_data() == dark.get_data())
	var source_bounds: Rect2i = original.texture.get_image().get_used_rect()
	var expected_size := Vector2(source_bounds.size) * original.scale.abs()
	var actual_size := Vector2(bright.get_used_rect().size)
	assert(actual_size.x > 0.0 and actual_size.y > 0.0)
	assert(
		(
			absf(actual_size.x - expected_size.x) <= 2.0
			and absf(actual_size.y - expected_size.y) <= 2.0
		),
		"Native opaque sprite bounds must retain the prefab's scale"
	)
	var peak := 0.0
	for y in bright.get_height():
		for x in bright.get_width():
			var color := bright.get_pixel(x, y)
			peak = maxf(peak, maxf(color.r, maxf(color.g, color.b)))
	if viewport.use_hdr_2d:
		assert(peak > 2.0, "Native GlowGlobal radiance must survive before bloom")
	else:
		assert(peak > 0.9)
	bright.save_png("res://tmp/art-direction/inari_kunai_material.png")
	print("KUNAI_RENDERING_GPU bounds=", bright.get_used_rect(), " peak=", peak)
	viewport.queue_free()
	await process_frame


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
