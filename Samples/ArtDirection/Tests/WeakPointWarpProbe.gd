extends SceneTree
## Compare the source marker's alpha with DXBC program 2634 at fixed times.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var info := Assets.sprite_info("sharedassets2_2525")
	var source := Assets.material_info("Mat_EnemyWeakness 5")
	var texture_info: Dictionary = info.effect_mesh.texture
	assert(texture_info.filter == 0 and texture_info.wrap_u == 1)
	assert(not info.effect_mesh.triangles.is_empty())
	assert(source.uv_effects.parameters._WarpScale > 0.0)
	var texture: Texture2D = load(Assets.ROOT + texture_info.path)
	var original := texture.get_image()
	original.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(original.get_data())
	assert(hash.finish().hex_encode() == texture_info.pixel_sha256)
	if DisplayServer.get_name() == "headless":
		print("WEAK_POINT_WARP_PASS (source data; GPU check requires a rendering backend)")
		quit()
		return

	var viewport := SubViewport.new()
	var scale_factor := 4
	viewport.size = original.get_size() * scale_factor
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != &"gl_compatibility"
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * scale_factor
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = Glow
	sprite.material = material
	Settings.configure(material, source, viewport.use_hdr_2d)
	material.set_shader_parameter("material_tint", Color.WHITE)
	var first: Image
	for time in [0.0, 0.125, 0.5, 1.0]:
		material.set_shader_parameter("uv_effect_time", time)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var mismatches := 0
		var changed := 0
		for y in range(0, viewport.size.y, 2):
			for x in range(0, viewport.size.x, 2):
				var uv := Vector2((x + 0.5) / viewport.size.x, 1.0 - (y + 0.5) / viewport.size.y)
				var sample_uv := _source_uv(uv, time, source.uv_effects)
				var texel := Vector2i(
					clampi(
						int(floor(sample_uv.x * original.get_width())), 0, original.get_width() - 1
					),
					clampi(
						int(floor((1.0 - sample_uv.y) * original.get_height())),
						0,
						original.get_height() - 1
					)
				)
				if absf(actual.get_pixel(x, y).a - original.get_pixelv(texel).a) > 0.02:
					mismatches += 1
				if (
					first != null
					and absf(actual.get_pixel(x, y).a - first.get_pixel(x, y).a) > 0.02
				):
					changed += 1
		print("WARP_GPU t=", time, " mismatches=", mismatches, " changed=", changed)
		assert(mismatches <= 8, "Warp disagrees with the shipped pixel program")
		if first == null:
			first = actual
		else:
			assert(changed > 0, "The original marker must deform over time")
	viewport.queue_free()
	await process_frame
	print("WEAK_POINT_WARP_PASS")
	quit()


func _source_uv(uv: Vector2, time: float, effects: Dictionary) -> Vector2:
	var st: Array = effects._MainTex_ST
	var parameters: Dictionary = effects.parameters
	var scale := Vector2(st[0], st[1])
	uv = uv * scale + Vector2(st[2], st[3])
	var phase := uv / scale * TAU / float(parameters._WarpScale)
	phase += Vector2.ONE * time * float(parameters._WarpSpeed)
	return uv + Vector2(sin(phase.x), sin(phase.y)) * float(parameters._WarpStrength)
