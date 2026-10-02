extends SceneTree
## Native player material, independent water lights and actual animation pixels.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	var original: Sprite2D = player.sprite
	var source: Dictionary = original.renderer
	var main: ShaderMaterial = original.material
	var reflection: Sprite2D = lab.water_capture.actor_pairs[0].copy
	var water: ShaderMaterial = reflection.material
	assert(source.sort == player.tuning.sprite_sort)
	assert(source.material.shader == "AllIn1SpriteShader/AllIn1Urp2dRenderer")
	assert(source.material.lighting_mask == [1.0, 1.0, 1.0])
	assert(source.program.keywords == ["GLOWLIGHT_ON", "GLOW_ON", "INNEROUTLINE_ON"])
	assert(main.shader.resource_path.ends_with("OriginalLit.gdshader"))
	assert(water.shader == main.shader and water != main)
	var id := int(source.layer_id)
	assert(main.get_shader_parameter("light_data") == lab.stage.lighting.layers[id].texture)
	assert(
		water.get_shader_parameter("light_data") == lab.water_capture.lighting.layers[id].texture
	)
	assert(water.get_shader_parameter("light_data") != main.get_shader_parameter("light_data"))
	assert(not water.get_shader_parameter("linear_framebuffer"))
	assert(main.get_shader_parameter("glow_affects_light"))
	assert(main.get_shader_parameter("inner_outline_enabled"))
	assert(main.get_shader_parameter("inner_outline_alpha") == 0.0)
	assert(main.get_shader_parameter("glow_amount") == 0.0)
	for clip in ["idle", "run", "attack1", "weak_dash_ready"]:
		original.play(clip)
		original.advance(0.05)
		lab.water_capture._process(0.0)
		assert(original.material == main and reflection.texture == original.texture)
		assert(reflection.transform == original.global_transform)
	original.modulate.a = 0.1
	main.set_shader_parameter("inner_outline_alpha", 0.4)
	lab.water_capture._process(0.0)
	assert(is_equal_approx(reflection.modulate.a, 0.1))
	assert(is_equal_approx(water.get_shader_parameter("inner_outline_alpha"), 0.4))
	var shared: ShaderMaterial = lab.stage.lighting.material_variants[str(id) + ":player"]
	assert(shared != main and shared.get_shader_parameter("inner_outline_alpha") == 0.0)
	main.set_shader_parameter("inner_outline_alpha", 0.0)
	original.modulate.a = 1.0
	original.play("idle")
	if DisplayServer.get_name() != "headless":
		await verify_gpu(original)
	lab.queue_free()
	await process_frame
	print("PLAYER_RENDERING_PASS")
	quit()


func verify_gpu(original: Sprite2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = original.texture
	sprite.texture_filter = original.texture_filter
	sprite.position = Vector2(64, 64)
	sprite.scale = Vector2(2, 2)
	sprite.material = original.material.duplicate()
	viewport.add_child(sprite)
	var material: ShaderMaterial = sprite.material
	material.set_shader_parameter("linear_framebuffer", viewport.use_hdr_2d)
	material.set_shader_parameter("light_count", 0)
	material.set_shader_parameter("ambient", Vector3.ONE)
	await draw_frames()
	var bright: Image = viewport.get_texture().get_image()
	material.set_shader_parameter("ambient", Vector3.ZERO)
	await draw_frames()
	var dark: Image = viewport.get_texture().get_image()
	material.set_shader_parameter("ambient", Vector3(0.25, 0.25, 0.25))
	await draw_frames()
	var dim: Image = viewport.get_texture().get_image()
	var checked := 0
	var error := 0.0
	for y in bright.get_height():
		for x in bright.get_width():
			var a := bright.get_pixel(x, y)
			if a.a < 0.9 or maxf(a.r, maxf(a.g, a.b)) < 0.1:
				continue
			var b := dim.get_pixel(x, y)
			var black := dark.get_pixel(x, y)
			assert(maxf(black.r, maxf(black.g, black.b)) < 0.005)
			if not viewport.use_hdr_2d:
				a = a.srgb_to_linear()
				b = b.srgb_to_linear()
			for channel in 3:
				error = maxf(error, absf(b[channel] - a[channel] * 0.25))
			checked += 1
	assert(checked > 100 and error < 0.015, "Native player pixels must respond to layer light")
	material.set_shader_parameter("ambient", Vector3.ONE)
	sprite.modulate.a = 0.1
	await draw_frames()
	var faded: Image = viewport.get_texture().get_image()
	var largest_alpha := 0.0
	for y in faded.get_height():
		for x in faded.get_width():
			largest_alpha = maxf(largest_alpha, faded.get_pixel(x, y).a)
	assert(absf(largest_alpha - 0.1) < 0.01)
	bright.save_png("res://tmp/art-direction/inari_player_material.png")
	print("PLAYER_RENDERING_GPU samples=", checked, " max_error=", error)
	viewport.queue_free()
	await process_frame


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
