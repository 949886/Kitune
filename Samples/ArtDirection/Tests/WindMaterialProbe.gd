extends SceneTree
## Check the recovered wind shader against its DXBC formula, including strict thresholds.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source := Assets.material_info("Mat_SavePoint")
	var proof: Dictionary = Assets.read_json(Assets.ROOT + "wind_material.json").Mat_SavePoint
	assert(proof.program.program_index == 32 and proof.program.parameter_index == 25)
	assert(source.color_change.tolerance == 0.25)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	var station_count := 0
	var native_texture: Texture2D
	for visual: Node in lab.stage.visual_instances:
		if visual.current_material != "Mat_SavePoint":
			continue
		assert(visual.material.get_shader_parameter("color_change_enabled"))
		assert(visual.material.shader == Glow)
		native_texture = visual.source
		station_count += 1
	assert(station_count == 2)
	lab.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await compare(source, native_texture, false)
		# These pixels are a numeric shader fixture, never a game art asset.
		var fixture := Image.create(8, 1, false, Image.FORMAT_RGBA8)
		var colors := [
			Color.RED,
			Color.GREEN,
			Color.BLUE,
			Color.WHITE,
			Color(0.9, 0.1, 0.05, 0.5),
			Color(0.7, 0.2, 0.1, 0.25),
			Color(0.4, 0.1, 0.6, 0.75),
			Color(0, 0, 0, 0)
		]
		for index in colors.size():
			fixture.set_pixel(index, 0, colors[index])
		await compare(source, ImageTexture.create_from_image(fixture), true)
	print("WIND_MATERIAL_PASS")
	quit()


func compare(source: Dictionary, texture: Texture2D, diagnostic: bool) -> void:
	var pixels := texture.get_image()
	var viewport := SubViewport.new()
	viewport.size = pixels.get_size()
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color.BLACK
	viewport.add_child(background)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	viewport.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = Glow
	Settings.configure(material, source, viewport.use_hdr_2d)
	sprite.material = material
	var cases: Array = [
		[float(source.color_change.tolerance), float(source.color_change.luminosity), Color.WHITE]
	]
	if diagnostic:
		cases = [
			[1.0, 0.0, Color.WHITE],
			[0.999, 0.0, Color.WHITE],
			[0.25, -0.5, Color.WHITE],
			[0.25, 1.0, Color.WHITE],
			[0.1, 0.1, Color(0.9, 0.7, 0.8, 0.6)]
		]
	var replacement := Assets.color(source.color_change.new_color)
	if diagnostic:
		replacement = Color(0.1, 0.8, 0.3)
	material.set_shader_parameter("color_change_new_color", replacement)
	var target := Assets.color(source.color_change.target).srgb_to_linear()
	var tint := Assets.color(source.color).srgb_to_linear()
	var glow := Assets.color(source.glow_color).srgb_to_linear()
	replacement = replacement.srgb_to_linear()
	for sample: Array in cases:
		material.set_shader_parameter("color_change_tolerance", sample[0])
		material.set_shader_parameter("color_change_luminosity", sample[1])
		sprite.modulate = sample[2]
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var error := 0.0
		var changed := 0
		for y in pixels.get_height():
			for x in pixels.get_width():
				var pixel := (
					pixels.get_pixel(x, y).srgb_to_linear() * sprite.modulate.srgb_to_linear()
				)
				var distance := (
					absf(pixel.r - target.r) + absf(pixel.g - target.g) + absf(pixel.b - target.b)
				)
				if 1.0 - minf(distance, 1.0) > float(sample[0]):
					var brightness := clampf(
						pixel.r * 0.3 + pixel.g * 0.59 + pixel.b * 0.11 + float(sample[1]), 0.0, 1.0
					)
					for channel in 3:
						pixel[channel] = brightness * replacement[channel]
					changed += 1
				var alpha := pixel.a
				for channel in 3:
					pixel[channel] *= (
						(
							float(source.glow_global)
							+ alpha * alpha * float(source.glow) * glow[channel]
						)
						* tint[channel]
					)
				pixel.a *= tint.a * float(source.alpha)
				if not viewport.use_hdr_2d:
					pixel = pixel.linear_to_srgb()
				var observed := actual.get_pixel(x, y)
				var maximum := 65504.0 if viewport.use_hdr_2d else 1.0
				for channel in 3:
					var expected := clampf(pixel[channel], 0.0, maximum) * pixel.a
					error = maxf(error, absf(observed[channel] - expected))
		assert(
			error < 0.015,
			"Wind color replacement, alpha or emission order differs from native DXBC"
		)
		if not diagnostic:
			assert(changed > 10, "Actual station pixels must exercise the recovered branch")
		if diagnostic and float(sample[0]) == 1.0:
			assert(changed == 0, "Equality must not replace the target color")
		print(
			"WIND_MATERIAL_GPU diagnostic=",
			diagnostic,
			" tolerance=",
			sample[0],
			" error=",
			error,
			" changed=",
			changed
		)
	viewport.queue_free()
	await process_frame
