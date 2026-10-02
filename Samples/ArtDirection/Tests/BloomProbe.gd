extends SceneTree
## Check source overrides, HDR energy, glow outside a sprite and frame ordering.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Bloom = preload("res://Samples/ArtDirection/Runtime/OriginalBloom.gd")
const GlowShader = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var settings: Dictionary = Assets.read_json(Assets.ROOT + "lighting.json").bloom
	assert(settings.effective.threshold == 0.0)
	assert(is_equal_approx(settings.effective.intensity, 0.2))
	assert(not settings.overrides.scatter and settings.effective.scatter == 0.7)
	assert(
		not settings.overrides.highQualityFiltering and not settings.effective.highQualityFiltering
	)

	if RenderingServer.get_current_rendering_method() not in [&"forward_plus", &"mobile"]:
		print("BLOOM_PROBE_PASS (source settings; HDR renderer required for GPU checks)")
		quit()
		return

	root.size = Vector2i(128, 128)
	var scene := SubViewport.new()
	# Native window minimum sizes differ across platforms; the fixture is 64².
	scene.size = Vector2i(64, 64)
	scene.use_hdr_2d = true
	scene.world_2d = World2D.new()
	scene.own_world_3d = true
	scene.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(scene)
	var background := ColorRect.new()
	background.size = Vector2(64, 64)
	background.color = Color.BLACK
	scene.add_child(background)
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(white)
	sprite.scale = Vector2(64, 64)
	sprite.position = Vector2(32, 32)
	var emission := ShaderMaterial.new()
	emission.shader = GlowShader
	emission.set_shader_parameter("glow_enabled", true)
	emission.set_shader_parameter("glow_global", 8.0)
	emission.set_shader_parameter("linear_framebuffer", true)
	sprite.material = emission
	scene.add_child(sprite)

	var bloom := Bloom.new()
	root.add_child(bloom)
	bloom.configure(scene, settings, root, -4.0)
	assert(bloom.mip_sizes == [Vector2i(32, 32), Vector2i(16, 16), Vector2i(8, 8), Vector2i(4, 4)])
	if DisplayServer.get_name() == "headless":
		print("BLOOM_PROBE_PASS (source settings and render graph)")
		quit()
		return
	var display := TextureRect.new()
	display.texture = scene.get_texture()
	display.material = bloom.presentation
	root.add_child(display)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw

	# A normalized blur must preserve a constant HDR field at every mip level.
	for pass_view in bloom.passes:
		var value := pass_view.get_texture().get_image().get_pixel(0, 0).r
		assert(absf(value - 8.0) < 0.02, "Bloom filter lost or clipped HDR energy")
	var flat := root.get_texture().get_image().get_pixel(32, 32).r
	var expected := Color(0.6, 0.6, 0.6).linear_to_srgb().r
	assert(absf(flat - expected) < 0.01, "Bloom must be added before post-exposure")

	sprite.scale = Vector2(2, 2)
	await process_frame
	await RenderingServer.frame_post_draw
	var halo := root.get_texture().get_image().get_pixel(36, 32).r
	assert(scene.get_texture().get_image().get_pixel(36, 32).r == 0.0)
	assert(halo > 0.003, "Bloom is missing outside the bright sprite")
	sprite.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var cleared := root.get_texture().get_image().get_pixel(36, 32).r
	assert(cleared == 0.0, "Bloom uses a previous frame instead of current scene radiance")
	print("BLOOM_GPU_PASS flat=", flat, " halo=", halo, " cleared=", cleared)
	print("BLOOM_PROBE_PASS")
	quit()
