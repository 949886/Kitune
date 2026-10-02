extends "res://Samples/ArtDirection/Tests/OriginalUVProbe.gd"
## Native factory quads, atlas UVs and point/linear sampling at fixed shader times.

const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const RENDERER_COUNTS = {"Mat_BGCLoud": 190, "Mat_LightDistotion 1": 2, "Mat_LightDistotion 3": 1}


func run() -> void:
	var proof: Dictionary = Assets.read_json(Assets.ROOT + "factory_uv.json")
	var scene: Dictionary = Assets.read_json(Assets.ROOT + "level15.json")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != &"gl_compatibility"
	root.add_child(viewport)
	for name: String in proof:
		var source := Assets.material_info(name)
		assert(proof[name].renderers.size() == RENDERER_COUNTS[name])
		assert(proof[name].fragment.program_sha256.length() == 64)
		var item: Dictionary
		for entry: Dictionary in scene.sprites:
			if entry.material == name:
				item = entry.duplicate(true)
				break
		var mesh: Dictionary = Assets.sprite_info(item.sprite).effect_mesh
		assert(mesh.vertices.size() == 4)
		for texture_info: Dictionary in [mesh.texture, source.uv_effects.noise]:
			var image := Image.load_from_file(Assets.ROOT + texture_info.path)
			image.convert(Image.FORMAT_RGBA8)
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data())
			assert(hash.finish().hex_encode() == texture_info.pixel_sha256)
			var imported := (load(Assets.ROOT + texture_info.path) as Texture2D).get_image()
			imported.convert(Image.FORMAT_RGBA8)
			assert(imported.get_data() == image.get_data(), "Texture import changed native pixels")
		item.color = [1, 1, 1, 1]
		item.flip = [false, false]
		var size := Assets.vec(mesh.vertices[3]) - Assets.vec(mesh.vertices[0])
		item.transform = [220.0 / size.x, 0, 0, 140.0 / size.y, 160, 90]
		var visual := Visual.new()
		viewport.add_child(visual)
		visual.configure(item)
		assert(visual.effect_texture != null)
		assert(visual.material.get_shader_parameter("distort_enabled"))
		assert(
			visual.material.get_shader_parameter("wind_enabled") == ("WIND_ON" in source.keywords)
		)
		# Compare UV sampling independently from the fog's native emission multiplier.
		visual.material.set_shader_parameter("glow_enabled", false)
		assert(
			visual.material.get_shader_parameter("source_bilinear") == (mesh.texture.filter == 1)
		)
		if DisplayServer.get_name() != "headless":
			noise = (load(Assets.ROOT + source.uv_effects.noise.path) as Texture2D).get_image()
			original = visual.effect_texture.get_image()
			await _compare(viewport, visual, source, mesh)
		visual.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
	await _verify_scene(proof)
	print("FACTORY_UV_PASS")
	quit()


func _verify_scene(proof: Dictionary) -> void:
	root.size = Vector2i(1280, 720)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	var found := false
	for index in lab.profiles.size():
		if lab.profiles[index].get("scene_data", "") != "level15.json":
			continue
		lab.load_level(index)
		found = true
		break
	assert(found)
	for frame in 30:
		await process_frame
	for name: String in proof:
		for go in proof[name].renderers:
			var visual: Node = lab.stage.visuals_by_go[go]
			assert(visual.current_material == name)
			assert(visual.material.get_shader_parameter("uv_effects_enabled"))
			assert(visual.material.get_shader_parameter("distort_enabled"))
			assert(
				(
					visual.material.get_shader_parameter("wind_enabled")
					== (name == "Mat_LightDistotion 3")
				)
			)
			assert(
				(
					visual.material.get_shader_parameter("glow_enabled")
					== ("GLOW_ON" in Assets.material_info(name).keywords)
				)
			)
			assert(visual.effect_texture != null)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/factory_uv_scene.png")
	lab.queue_free()
	await process_frame


func _compare(viewport: SubViewport, visual: Node, source: Dictionary, mesh: Dictionary) -> void:
	var opaque := Shader.new()
	# Keep production sampling/color math; force opacity only to read RGB without
	# transparent framebuffer blending. The unmodified shader separately checks alpha.
	opaque.code = Glow.code.replace("\tCOLOR = vec4(", "\tpixel.a = 1.0;\n\tCOLOR = vec4(")
	var first: Image
	for rgb in [false, true]:
		visual.material.shader = opaque if rgb else Glow
		var times := [0.0, 0.5, 2.0, 25.0] if "WIND_ON" in source.keywords else [0.0, 0.5, 2.0]
		for time in times:
			visual.material.set_shader_parameter("uv_effect_time", time)
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image()
			var mismatches := 0
			var changed := 0
			for y in range(22, 158, 4):
				for x in range(52, 268, 4):
					var fraction := Vector2((x + 0.5 - 50) / 220.0, (y + 0.5 - 20) / 140.0)
					var uv := (
						Assets.vec(mesh.uv[0])
						+ fraction * (Assets.vec(mesh.uv[3]) - Assets.vec(mesh.uv[0]))
					)
					var expected := _sample(_factory_uv(uv, time, source), mesh.texture.filter == 1)
					var pixel := actual.get_pixel(x, y)
					if rgb:
						if not viewport.use_hdr_2d:
							expected = expected.linear_to_srgb()
						if (
							maxf(
								absf(pixel.r - expected.r),
								maxf(absf(pixel.g - expected.g), absf(pixel.b - expected.b))
							)
							> 0.025
						):
							mismatches += 1
					elif absf(pixel.a - expected.a) > 0.025:
						mismatches += 1
					if not rgb and first != null and absf(pixel.a - first.get_pixel(x, y).a) > 0.01:
						changed += 1
			print(
				"FACTORY_UV_GPU ",
				source.name,
				" rgb=",
				rgb,
				" t=",
				time,
				" mismatches=",
				mismatches,
				" changed=",
				changed
			)
			assert(mismatches <= 8, "Native factory sampling differs from rendered output")
			if not rgb:
				if time == 0.0:
					first = actual
				else:
					assert(changed > 8, "Native distortion must animate")


func _factory_uv(godot_uv: Vector2, time: float, source: Dictionary) -> Vector2:
	var effects: Dictionary = source.uv_effects
	var p: Dictionary = effects.parameters
	var st: Array = effects._MainTex_ST
	var noise_st: Array = effects._DistortTex_ST
	var uv := Vector2(godot_uv.x, 1.0 - godot_uv.y)
	var noise_uv := uv * Vector2(noise_st[0], noise_st[1]) + Vector2(noise_st[2], noise_st[3])
	noise_uv += Vector2(
		fmod(time / 20.0 * p._DistortTexXSpeed, 1.0), fmod(time / 20.0 * p._DistortTexYSpeed, 1.0)
	)
	uv = uv * Vector2(st[0], st[1]) + Vector2(st[2], st[3])
	var original_uv := uv
	uv += Vector2.ONE * (_noise(noise_uv) - 0.5) * 0.2 * float(p._DistortAmount)
	if "WAVEUV_ON" in source.keywords:
		var direction := Vector2(p._WaveX * st[0], p._WaveY * st[1]) - uv
		direction = Vector2(fmod(direction.x, 1.0), fmod(direction.y, 1.0))
		direction.x *= 320.0 / 180.0
		uv += (
			direction
			* sin(direction.length() * p._WaveAmount - time * p._WaveSpeed)
			* p._WaveStrength
			/ 1000.0
		)
	if "WIND_ON" in source.keywords:
		var phase := sin(time * float(p._GrassSpeed) / 2.0)
		uv.x = fposmod(absf(uv.x + original_uv.y * phase * float(p._GrassWind) / 100.0), 1.0)
		var radial := uv - Vector2(0.5, 0.1)
		uv += (
			Vector2(radial.y, -radial.x)
			* radial.length_squared()
			* phase
			* float(p._GrassRadialBend)
		)
	return Vector2(uv.x, 1.0 - uv.y)


func _sample(uv: Vector2, bilinear: bool) -> Color:
	var size := Vector2(original.get_size())
	if not bilinear:
		return _texel(Vector2i((uv * size).floor()))
	var point := uv * size - Vector2.ONE * 0.5
	var base := Vector2i(point.floor())
	var weight := point - point.floor()
	var top := _texel(base).lerp(_texel(base + Vector2i.RIGHT), weight.x)
	var bottom := _texel(base + Vector2i.DOWN).lerp(_texel(base + Vector2i.ONE), weight.x)
	return top.lerp(bottom, weight.y)


func _texel(point: Vector2i) -> Color:
	point = point.clamp(Vector2i.ZERO, original.get_size() - Vector2i.ONE)
	return original.get_pixelv(point).srgb_to_linear()
