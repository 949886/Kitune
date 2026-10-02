extends SceneTree
## Source atlas integrity and pixel-program 2625's hit / outline / glow order.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "weakpoints.json")
	assert(evidence.outline.sprite_count == 525 and evidence.outline.textures.size() == 2)
	for info: Dictionary in evidence.outline.textures:
		var texture: Texture2D = load(Assets.ROOT + info.path)
		var pixels := texture.get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == info.pixel_sha256)
	if DisplayServer.get_name() != "headless":
		await verify_gpu()
	print("ENEMY_OUTLINE_PASS")
	quit()


func rgb(color: Color) -> Vector3:
	var linear := color.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b)


func verify_gpu() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return
	var info := Assets.sprite_info("sharedassets2_3394")
	var texture: Texture2D = load(Assets.ROOT + info.effect_mesh.texture.path)
	var pixels := texture.get_image()
	var bounds := Rect2(Assets.vec(info.effect_mesh.uv[0]), Vector2.ZERO)
	for uv: Array in info.effect_mesh.uv:
		bounds = bounds.expand(Assets.vec(uv))
	var origin := (
		Vector2i((bounds.position * Vector2(pixels.get_size())).floor()) - Vector2i.ONE * 2
	)
	var size := Vector2i((bounds.size * Vector2(pixels.get_size())).ceil()) + Vector2i.ONE * 4
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.world_2d = World2D.new()
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(size)
	background.color = Color.BLACK
	viewport.add_child(background)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = false
	sprite.region_rect = Rect2(origin, size)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var renderer_alpha := 0.6
	sprite.modulate.a = renderer_alpha
	var source := Assets.material_info("Mat_Enemy 5")
	assert(source.black_glow_mask)
	var material := ShaderMaterial.new()
	material.shader = Glow
	Settings.configure(material, source, true)
	sprite.material = material
	viewport.add_child(sprite)
	for amount in [0.0, 0.4, 1.0]:
		material.set_shader_parameter("base_outline_alpha", amount)
		material.set_shader_parameter("hit_blend", 0.3)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var maximum_error := 0.0
		var edge_pixels := 0
		for y in range(1, size.y - 1):
			for x in range(1, size.x - 1):
				var point := origin + Vector2i(x, y)
				var raw := pixels.get_pixelv(point)
				var neighbors := 0.0
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					neighbors += pixels.get_pixelv(point + offset).a
				var weight: float = (1.0 - raw.a) * amount if neighbors >= 0.05 else 0.0
				var surface := rgb(raw).lerp(
					rgb(Assets.color(source.hit_color)) * float(source.hit_glow), 0.3
				)
				var outline := (
					rgb(Assets.color(source.base_outline.color))
					* renderer_alpha
					* float(source.base_outline.glow)
				)
				surface = surface.lerp(outline, weight)
				var alpha := lerpf(raw.a * renderer_alpha, weight, weight)
				surface *= float(source.glow_global) * rgb(Assets.color(source.color))
				surface *= alpha * float(source.alpha) * float(source.color[3])
				var actual := image.get_pixel(x, y)
				var difference := (Vector3(actual.r, actual.g, actual.b) - surface).abs()
				var relative := difference / (Vector3.ONE + surface.abs())
				maximum_error = maxf(maximum_error, maxf(relative.x, maxf(relative.y, relative.z)))
				if weight > 0.0:
					edge_pixels += 1
		print(
			"ENEMY_OUTLINE_GPU alpha=",
			amount,
			" edge_pixels=",
			edge_pixels,
			" relative_error=",
			maximum_error
		)
		assert(maximum_error < 0.004, "Native hit / outline / glow formula mismatch")
		if amount > 0.0:
			assert(edge_pixels > 20)
	viewport.queue_free()
	await process_frame
