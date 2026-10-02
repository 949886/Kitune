extends SceneTree
## Exercise source layer IDs and actual GPU light/exposure output on known pixels.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Lighting = preload("res://Samples/ArtDirection/Runtime/OriginalLighting.gd")
const SceneProjection = preload("res://Samples/ArtDirection/Runtime/OriginalSceneProjection.gd")
const GlowShader = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1024, 64)
	# Exercise the same HDR game texture -> sRGB UI boundary as the actual lab.
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.world_2d = World2D.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var factory: Dictionary = Assets.read_json(Assets.ROOT + "level15.json")
	var point: Dictionary
	for light: Dictionary in factory.lights:
		if light.energy == 30.0 and light.radius == 400.0:
			point = light.duplicate(true)
			break
	assert(not point.is_empty())
	# Move an unchanged source lamp onto the pixel fixture; preserve its color,
	# energy, radii, falloff and normal-distance settings.
	point.spatial.transform = [1, 0, 0, 1, 512.5, 32.5]
	point.spatial.depth = 0.0

	var projection := SceneProjection.new()
	viewport.add_child(projection)
	projection.configure(Assets.read_json(Assets.ROOT + "camera.json"))
	var lighting := Lighting.new()
	viewport.add_child(lighting)
	lighting.configure({"lights": [point]}, projection)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.material = lighting.display_material(root)
	root.add_child(display)

	var pixels := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(pixels)
	sprite.scale = Vector2(1024, 64)
	sprite.position = Vector2(512, 32)
	viewport.add_child(sprite)

	# JSON float IDs must match signed integer sorting-layer IDs.
	lighting.apply_to(sprite, {"material": "Mat_Default", "layer_id": -256207055})
	assert(sprite.material.get_shader_parameter("ambient") == Vector3(0.5, 0.5, 0.5))
	assert(sprite.material.get_shader_parameter("light_count") == 0)
	lighting.apply_to(sprite, {"material": "Mat_Default", "layer_id": 2147483000})
	assert(sprite.material.get_shader_parameter("ambient") == Vector3.ONE)
	assert(sprite.material.get_shader_parameter("light_count") == 0)
	lighting.apply_to(sprite, {"material": "Mat_Default", "layer_id": 1857066909})
	assert(sprite.material.get_shader_parameter("ambient") == Vector3.ONE)
	assert(sprite.material.get_shader_parameter("light_count") == 1)
	assert(is_equal_approx(lighting.exposure_material.get_shader_parameter("exposure_stops"), 1.7))

	if DisplayServer.get_name() != "headless":
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		var outside := rendered.get_pixel(0, 32)
		var middle := rendered.get_pixel(312, 32)
		var center := rendered.get_pixel(512, 32)
		var original := Color(32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0).srgb_to_linear()
		var exposed := (original * pow(2.0, 1.7)).linear_to_srgb()
		assert(absf(outside.r - exposed.r) < 0.015, "Exposure must be applied in linear space")
		assert(absf(center.b - outside.b) < 0.015, "Orange source light must not brighten blue")
		assert(center.r > 0.95 and center.g > outside.g + 0.2)
		assert(middle.r > outside.r + 0.05 and middle.r < center.r - 0.2)
		rendered.save_png("res://tmp/art-direction/lighting-fixture.png")
		print("LIGHTING_GPU_PASS ", outside, " / ", middle, " / ", center)
		if lighting.linear_framebuffer:
			var hdr := viewport.get_texture().get_image()
			assert(hdr.get_pixel(512, 32).r > 1.2, "HDR radiance was clipped before display")
			assert(absf(hdr.get_pixel(0, 32).r - original.r * pow(2.0, 1.7)) < 0.002)
			print("LIGHTING_HDR_PASS ", hdr.get_pixel(512, 32))
			await _verify_emission(viewport, sprite, lighting)
			await _verify_source_materials(viewport, sprite, lighting)

	lighting.queue_free()
	projection.queue_free()
	sprite.queue_free()
	display.queue_free()
	viewport.queue_free()
	await process_frame
	print("LIGHTING_PROBE_PASS")
	quit()


func _verify_emission(viewport: SubViewport, sprite: Sprite2D, lighting: Node) -> void:
	# Reducing exposure must recover a bright material's original radiance.
	# A buffer clipped at white would return 1/16 instead of 8/16 here.
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(white)
	var glow := ShaderMaterial.new()
	glow.shader = GlowShader
	glow.set_shader_parameter("glow_enabled", true)
	glow.set_shader_parameter("glow_global", 8.0)
	glow.set_shader_parameter("linear_framebuffer", true)
	sprite.material = glow
	lighting.exposure_material.set_shader_parameter("exposure_stops", -4.0)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw

	var linear := viewport.get_texture().get_image().get_pixel(512, 32)
	var displayed := root.get_texture().get_image().get_pixel(512, 32)
	assert(absf(linear.r - 0.5) < 0.002, "Emission clipped before negative exposure")
	assert(absf(displayed.r - Color(0.5, 0.5, 0.5).linear_to_srgb().r) < 0.01)
	print("LIGHTING_EMISSION_PASS ", linear, " / ", displayed)


func _verify_source_materials(viewport: SubViewport, sprite: Sprite2D, lighting: Node) -> void:
	lighting.exposure_screen.hide()
	var black := ColorRect.new()
	black.size = Vector2(viewport.size)
	black.color = Color.BLACK
	viewport.add_child(black)
	viewport.move_child(black, 0)

	# Mat_Light 12 has colored glow=0 but global glow=4.2 and alpha=.893.
	# Its source output over black is 3.7506, rather than an unlit value of .893.
	var glow := ShaderMaterial.new()
	glow.shader = GlowShader
	MaterialSettings.configure(glow, Assets.material_info("Mat_Light 12"), true)
	sprite.material = glow
	var global_only := await _hdr_pixel(viewport)
	assert(absf(global_only.r - 3.7506) < 0.015, "Global glow was omitted")

	# The source GLOWLIGHT_ON program mixes lit and unlit surface radiance.
	# This shipped cutscene material on the source half-strength global layer
	# yields .68439; skipping lights entirely yields approximately 1.17 instead.
	lighting.apply_to(sprite, {"material": "Player _Cutscene", "layer_id": -256207055})
	var mixed := await _hdr_pixel(viewport)
	assert(
		absf(mixed.r - 0.68438964) < 0.01,
		"Glow/light composition does not match the source program"
	)

	# Renderer alpha participates in colored glow before material alpha is applied.
	var translucent := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	translucent.fill(Color(1.0, 1.0, 1.0, 128.0 / 255.0))
	sprite.texture = ImageTexture.create_from_image(translucent)
	glow.set_shader_parameter("glow_global", 1.0)
	glow.set_shader_parameter("glow_amount", 4.0)
	glow.set_shader_parameter("material_alpha", 0.5)
	sprite.material = glow
	var transparent := await _hdr_pixel(viewport)
	assert(absf(transparent.r - 0.50393312) < 0.005, "Material alpha was applied before emission")
	print("LIGHTING_MATERIAL_PASS ", global_only, " / ", mixed, " / ", transparent)
	await _verify_hit_flash(viewport, sprite, glow)


func _verify_hit_flash(viewport: SubViewport, sprite: Sprite2D, glow: ShaderMaterial) -> void:
	# Keep a partially transparent texel: hit color replaces RGB before emission,
	# while the original alpha still controls colored glow and final blending.
	var texel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	texel.fill(Color(0.0, 0.0, 0.0, 128.0 / 255.0))
	sprite.texture = ImageTexture.create_from_image(texel)
	glow.set_shader_parameter("hit_enabled", true)
	glow.set_shader_parameter("hit_tint", Color.WHITE)
	glow.set_shader_parameter("hit_glow", 2.0)
	glow.set_shader_parameter("hit_blend", 0.8)
	var flashed := await _hdr_pixel(viewport)
	# RGB = lerp(0, 2, .8) * (1 + alpha² * 4), then alpha * .5 over black.
	assert(absf(flashed.r - 0.80629299) < 0.008, "Hit flash changed source alpha or glow order")
	glow.set_shader_parameter("hit_blend", 0.0)
	var cleared := await _hdr_pixel(viewport)
	assert(cleared.r < 0.002, "Hit flash did not clear")
	print("LIGHTING_HIT_PASS ", flashed, " / ", cleared)


func _hdr_pixel(viewport: SubViewport) -> Color:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(512, 32)
