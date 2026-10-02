extends SceneTree
## Check dark values, the sRGB transfer knee, alpha and actual HDR/LDR readbacks.

const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")
const VALUES := [0.0, 0.0001, 0.002, 0.0031308, 0.004, 0.018, 0.18, 0.5, 1.0, 4.0]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source := Image.create(VALUES.size(), 1, false, Image.FORMAT_RGBAF)
	for index in VALUES.size():
		source.set_pixel(index, 0, Color(VALUES[index], VALUES[index], VALUES[index], 0.4))
	var original := source.get_data()
	var encoded := Capture.for_png(source, true)
	assert(source.get_data() == original, "Export must preserve the radiance readback")
	assert(encoded.get_format() == Image.FORMAT_RGBA8)
	for index in VALUES.size():
		_check(encoded.get_pixel(index, 0), VALUES[index], 0.4)
	var unchanged := Capture.for_png(encoded, false)
	assert(unchanged.get_data() == encoded.get_data(), "LDR must not receive a second sRGB encode")
	if DisplayServer.get_name() != "headless":
		await _verify_gpu(false)
		if RenderingServer.get_current_rendering_method() != &"gl_compatibility":
			await _verify_gpu(true)
	print("VIEWPORT_CAPTURE_PASS")
	quit()


func _verify_gpu(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VALUES.size() * 8, 8)
	viewport.use_hdr_2d = hdr
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform vec4 fixture;
void fragment() { COLOR = fixture; }
"""
	for index in VALUES.size():
		var quad := ColorRect.new()
		quad.position = Vector2(index * 8, 0)
		quad.size = Vector2(8, 8)
		var material := ShaderMaterial.new()
		material.shader = shader
		var value: float = VALUES[index] if hdr else _encode(VALUES[index])
		material.set_shader_parameter("fixture", Vector4(value, value, value, 0.4))
		quad.material = material
		viewport.add_child(quad)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://tmp/art-direction/capture_fixture_%s.png" % str(hdr)
	assert(Capture.save_png(viewport, path) == OK)
	var saved := Image.new()
	assert(saved.load(path) == OK)
	for index in VALUES.size():
		_check(saved.get_pixel(index * 8 + 4, 4), VALUES[index], 0.4)
	viewport.queue_free()
	await process_frame


func _check(pixel: Color, linear: float, alpha: float) -> void:
	var expected := clampf(_encode(linear), 0.0, 1.0)
	assert(absf(pixel.r - expected) <= 1.0 / 255.0)
	assert(absf(pixel.g - expected) <= 1.0 / 255.0)
	assert(absf(pixel.b - expected) <= 1.0 / 255.0)
	assert(absf(pixel.a - alpha) <= 1.0 / 255.0)


func _encode(value: float) -> float:
	return value * 12.92 if value <= 0.0031308 else 1.055 * pow(value, 1.0 / 2.4) - 0.055
