extends SceneTree
## Native marker resources, overlapping fades, frame ordering and dotted-line pixels.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source: Dictionary = Assets.read_json(Assets.ROOT + "target_marker.json")
	assert(source.fade_in == 0.0 and is_equal_approx(source.disappear_time, 0.2))
	assert(source.light.energy == 16.0 and source.light.radius == 16.0)
	assert(source.programs.Mat_dotline.program_index == 3)
	assert(source.programs.Mat_WeakTarget.program_index == 2605)
	var textures: Array = [source.line.texture]
	for sprite: Dictionary in source.sprites:
		textures.append(Assets.sprite_info(sprite.sprite).effect_mesh.texture)
	for info: Dictionary in textures:
		var texture: Texture2D = load(Assets.ROOT + info.path)
		var pixels := texture.get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == info.pixel_sha256)

	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
	var first: Node = lab.stage.enemies[0]
	var second: Node = lab.stage.enemies[1]
	var marker: Node = player.targeting.presentation
	marker.set_process(false)
	assert(not marker.marker.visible and not marker.line.visible)
	assert(marker.visuals.filter(func(visual: Node2D): return visual.visible).size() == 1)
	assert(is_equal_approx(marker.visuals[0].scale.x, 7.94111967086792))
	marker.update_line(null)
	assert(marker.line.points[1] == Vector2(160, 0))
	marker.update_selection(first, true, false)
	assert(marker.marker.visible and marker.line.visible)
	assert(marker.fades.size() == 3 and marker.visuals[0].modulate.a == 0.0)
	marker.advance(0.0)
	assert(marker.visuals[0].modulate.a == 1.0)
	assert(marker.light.enabled)
	assert(marker.marker.global_position == first.global_position + first.body_shape.position)
	marker.update_line(first)
	var old_points: PackedVector2Array = marker.line.points
	marker.update_selection(second, true, false)
	assert(marker.line.points == old_points, "Native endpoint calculation precedes selection")
	assert(marker.marker.global_position == second.global_position + second.body_shape.position)
	assert(marker.fades.size() == 3)
	marker.advance(float(source.disappear_time) * 0.5)
	assert(is_equal_approx(marker.visuals[0].modulate.a, 0.25))
	assert(marker.light.enabled, "The child light does not fade with sprite alpha")
	marker.update_selection(second, true, true)
	assert(marker.line.visible, "Same-target gamepad switch retains an existing mouse line")
	marker.advance(float(source.disappear_time) * 0.5)
	assert(not marker.marker.visible and not marker.light.enabled)
	marker.update_selection(second, true, true)
	assert(marker.marker.visible)
	marker.advance(0.0)
	marker.update_selection(null, false, true)
	marker.advance(0.05)
	marker.update_selection(null, false, true)
	assert(marker.fades.size() == 6, "Repeated native hide calls overlap")
	assert(marker.visuals[0].modulate.a == 1.0)
	marker.advance(float(source.disappear_time))
	assert(not marker.marker.visible and not marker.line.visible)
	marker.update_selection(first, true, true)
	assert(marker.marker.visible and not marker.line.visible)
	marker.advance(0.0)

	# A moving point light must update even with a stationary camera. Its radius
	# is a URP world-space property, independent of the marker's 7.94 scale.
	first.position += Vector2(13, 7)
	marker.update_selection(first, true, true)
	lab.stage.lighting._process(0.0)
	var checked := 0
	for layer: Dictionary in lab.stage.lighting.layers.values():
		var index: int = layer.lights.find(marker.light)
		if index < 0:
			continue
		var bounds: Color = layer.buffer.get_pixel(0, index)
		assert(Vector2(bounds.r, bounds.g).is_equal_approx(marker.marker.global_position))
		assert(bounds.b == 16.0)
		assert(layer.buffer.get_pixel(1, index).r == 16.0)
		checked += 1
	assert(checked > 0)
	marker.reset()
	assert(not marker.marker.visible and not marker.line.visible and not marker.light.enabled)
	if DisplayServer.get_name() != "headless":
		await verify_line(marker.line, source.line)
	lab.load_level(1)
	assert(lab.water_capture != null)
	assert(lab.water_capture.marker_pairs.size() == source.sprites.size() + 1)
	assert(lab.water_capture.line_pairs.size() == 2)
	assert(
		is_same(lab.stage.lighting.runtime_lights[0], lab.water_capture.lighting.runtime_lights[0])
	)
	lab.queue_free()
	await process_frame
	print("TARGET_MARKER_PASS")
	quit()


func verify_line(original: Line2D, source: Dictionary) -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(224, 224)
	viewport.world_2d = World2D.new()
	viewport.use_hdr_2d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var line := original.duplicate() as Line2D
	line.material = original.material.duplicate()
	line.material.set_shader_parameter("linear_framebuffer", true)
	line.material.set_shader_parameter("endpoint_depth", 0.0)
	line.position = Vector2(40, 40)
	line.show()
	viewport.add_child(line)
	var pixels := line.texture.get_image()
	var gradient: Dictionary = source.parameters.colorGradient.key0
	var tint := Color(gradient.r, gradient.g, gradient.b, gradient.a).srgb_to_linear()
	for angle in [0.0, 0.61, PI * 0.5]:
		var direction := Vector2.from_angle(angle)
		var normal := direction.orthogonal()
		line.points = PackedVector2Array([Vector2.ZERO, direction * 144.0])
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var maximum_error := 0.0
		var tested := 0
		var solid := 0
		var reported := 0
		for y in image.get_height():
			for x in image.get_width():
				var offset := Vector2(x + 0.5, y + 0.5) - line.position
				var along := offset.dot(direction)
				var across := offset.dot(normal)
				if along < 3.0 or along > 141.0 or absf(across) > line.width * 0.5 - 1.0:
					continue
				var du := maxf(absf(direction.x), absf(direction.y)) / 144.0 + 0.0000001
				var distance := (1.0 / 16.0) / du * (along / 144.0)
				var period: float = source.dash_length + source.gap_length
				var phase := fposmod(distance / period, 1.0)
				var ratio: float = source.dash_length / period
				var uv := Vector2(phase / ratio, 0.5 - across / line.width)
				# Derivative precision can choose either neighboring nearest texel at
				# an exact boundary. Compare the interiors of both lit and gap pixels.
				var texture_position := uv * Vector2(pixels.get_size())
				if absf(texture_position.x - roundf(texture_position.x)) < 0.002:
					continue
				if absf(texture_position.y - roundf(texture_position.y)) < 0.002:
					continue
				var texel := Vector2i((uv * Vector2(pixels.get_size())).floor())
				texel = texel.clamp(Vector2i.ZERO, pixels.get_size() - Vector2i.ONE)
				var expected := pixels.get_pixelv(texel).srgb_to_linear() * tint
				expected.a *= 1.0 if phase <= ratio else 0.0
				var actual := image.get_pixel(x, y)
				if absf(actual.r - expected.r * expected.a) > 0.01 and reported < 4:
					print(
						"LINE_MISMATCH pixel=",
						Vector2i(x, y),
						" uv=",
						uv,
						" actual=",
						actual,
						" expected=",
						expected
					)
					reported += 1
				var delta := (
					Vector3(actual.r, actual.g, actual.b)
					- Vector3(expected.r, expected.g, expected.b) * expected.a
				)
				maximum_error = maxf(
					maximum_error, maxf(absf(delta.x), maxf(absf(delta.y), absf(delta.z)))
				)
				tested += 1
				if expected.a > 0.0:
					solid += 1
		print(
			"TARGET_LINE_GPU angle=",
			angle,
			" pixels=",
			tested,
			" lit=",
			solid,
			" error=",
			maximum_error
		)
		assert(tested > 100 and solid > 20)
		assert(maximum_error < 0.004, "Native derivative / dash texture / color formula mismatch")
	viewport.queue_free()
	await process_frame
