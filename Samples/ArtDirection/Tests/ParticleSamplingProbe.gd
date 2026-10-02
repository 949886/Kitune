extends SceneTree
## Compare the original particle masks with a CPU reading of the shipped programs.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var data: Dictionary = Assets.read_json(Assets.ROOT + "Particles/effects.json")
	var materials: Dictionary = {}
	for effect: Dictionary in data.effects.values():
		for emitter: Dictionary in effect.emitters:
			if emitter.material.has("particle_sampling"):
				materials[emitter.material.name] = emitter
	assert(materials.size() == 5)
	for entry: Dictionary in materials.values():
		var source: Dictionary = entry.material
		assert(source.shader_proof.program_sha256.length() == 64)
		var texture: Texture2D = load(Assets.ROOT + "Particles/" + entry.texture.path)
		var pixels := texture.get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == entry.texture.pixel_sha256)
		if DisplayServer.get_name() != "headless":
			await compare(entry, texture, pixels)
			if "PIXELATE_ON" in source.keywords:
				# The shipped slash is square. Crop its existing pixels in memory
				# to also detect reversed width/height in the native grid formula.
				var crop := pixels.get_region(
					Rect2i(0, 0, pixels.get_width(), pixels.get_height() / 2)
				)
				await compare(entry, ImageTexture.create_from_image(crop), crop)
	print("PARTICLE_SAMPLING_PASS")
	quit()


func sample(pixels: Image, uv: Vector2, linear: bool) -> float:
	var bounds := pixels.get_size() - Vector2i.ONE
	if not linear:
		var point := Vector2i((uv * Vector2(pixels.get_size())).floor())
		return pixels.get_pixelv(point.clamp(Vector2i.ZERO, bounds)).a
	var point := uv * Vector2(pixels.get_size()) - Vector2(0.5, 0.5)
	var low := Vector2i(point.floor())
	var weight := point - Vector2(low)
	var a := pixels.get_pixelv(low.clamp(Vector2i.ZERO, bounds)).a
	var b := pixels.get_pixelv((low + Vector2i.RIGHT).clamp(Vector2i.ZERO, bounds)).a
	var c := pixels.get_pixelv((low + Vector2i.DOWN).clamp(Vector2i.ZERO, bounds)).a
	var d := pixels.get_pixelv((low + Vector2i.ONE).clamp(Vector2i.ZERO, bounds)).a
	return lerpf(lerpf(a, b, weight.x), lerpf(c, d, weight.x), weight.y)


func expected_alpha(pixels: Image, point: Vector2, entry: Dictionary) -> float:
	var source: Dictionary = entry.material
	var uv := Vector2(point.x, 1.0 - point.y)
	if "PINCH_ON" in source.keywords:
		var center := Vector2(0.5, 0.5)
		var radial := uv - center
		var coefficient: float = (
			(0.001 - source.floats._PinchUvAmount) * 3.141592025756836 / center.length()
		)
		# Mathematical atan is an independent oracle for the native DXBC
		# polynomial. Its approximation error is below the mask tolerance.
		uv = (
			center
			+ (
				radial.normalized()
				* 0.5
				* atan(-10.0 * coefficient * radial.length())
				/ atan(-5.0 * coefficient)
			)
		)
	if "PIXELATE_ON" in source.keywords:
		var grid := (
			Vector2(1.0, float(pixels.get_height()) / pixels.get_width())
			* float(source.floats._PixelateSize)
		)
		uv = (uv * grid).floor() / grid
	uv.y = 1.0 - uv.y
	if "BLUR_ON" not in source.keywords:
		return sample(pixels, uv, entry.texture.filter != 0)
	var distance: float = source.floats._BlurIntensity / 256.0
	# Enumerate all nine source taps independently, including its duplicate.
	var taps := [
		Vector2(-1, 1),
		Vector2(-1, 0),
		Vector2(-1, -1),
		Vector2(0, 1),
		Vector2.ZERO,
		Vector2(0, -1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(1, 1)
	]
	var weights := [1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0]
	var result := 0.0
	for index in taps.size():
		result += sample(pixels, uv + taps[index] * distance, true) * weights[index] / 16.0
	return result


func compare(entry: Dictionary, texture: Texture2D, pixels: Image) -> void:
	var target := SubViewport.new()
	target.size = Vector2i(192, 160)
	target.transparent_bg = true
	target.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2(target.size) / Vector2(pixels.get_size())
	sprite.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if entry.texture.filter == 0
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	target.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = Glow
	Settings.configure(material, entry.material, target.use_hdr_2d)
	material.set_shader_parameter("material_tint", Color.WHITE)
	material.set_shader_parameter("material_alpha", 1.0)
	material.set_shader_parameter("glow_enabled", false)
	sprite.material = material
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var actual := target.get_texture().get_image()
	var max_error := 0.0
	var changed := 0
	for y in range(0, target.size.y, 2):
		for x in range(0, target.size.x, 2):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(target.size)
			var expected := expected_alpha(pixels, uv, entry)
			max_error = maxf(max_error, absf(expected - actual.get_pixel(x, y).a))
			if absf(expected - sample(pixels, uv, entry.texture.filter != 0)) > 0.01:
				changed += 1
	print(
		"PARTICLE_SAMPLING_GPU ",
		entry.material.name,
		" max_error=",
		max_error,
		" changed=",
		changed
	)
	assert(max_error < 0.02, "Particle mask differs from the native shader")
	if "PINCH_ON" not in entry.material.keywords or entry.material.floats._PinchUvAmount > 0.0:
		assert(changed > 0)
	target.queue_free()
	await process_frame
