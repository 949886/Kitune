extends SceneTree
## Native water data, reflection isolation, animated actors and GPU pixel math.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Water = preload("res://Samples/ArtDirection/Runtime/OriginalWater.gd")

var normal: Image


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source := Water.source_settings()
	assert(source.program.bindings.UnityPerMaterial._Tilling == 24)
	assert(source.material._Tilling == 2.0 and source.normal.mips.size() == 10)
	assert(source.normal.color_space == 0 and source.normal.settings.m_FilterMode == 1)
	var packed := Water.normal_texture().get_image()
	assert(packed.has_mipmaps() and packed.get_mipmap_count() == 9)
	var bytes := packed.get_data()
	for level in source.normal.mips.size():
		var mip: Dictionary = source.normal.mips[level]
		var offset := packed.get_mipmap_offset(level)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes.slice(offset, offset + int(mip.width * mip.height * 4)))
		assert(hash.finish().hex_encode() == mip.rgba_sha256, "Native mip pixels changed")
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var capture: Node = lab.water_capture
	assert(capture.viewport.size == Vector2i(1920, 1080))
	assert(capture.viewport.world_2d != lab.viewport.world_2d)
	assert(not capture.viewport.use_hdr_2d and not capture.lighting.exposure_screen.visible)
	var height := 42.0 * tan(deg_to_rad(61.5)) * 16.0
	assert(capture.view_size.distance_to(Vector2(height, height)) < 0.001)
	assert(
		capture.stage_pairs.size() + capture.surfaces.size() == lab.stage.visual_instances.size()
	)
	lab.camera_rig.set_process(false)
	var previous_center: Vector2 = capture.camera.position
	lab.camera.position += Vector2(93, -173)
	lab.camera.force_update_scroll()
	capture._process(0.0)
	assert(capture.camera.position == previous_center, "Water camera moves on the fixed clock")
	capture._physics_process(0.0)
	capture._process(0.0)
	assert(capture.camera.position.distance_to(Vector2(lab.camera.position.x, -688)) < 0.001)
	for surface: Node2D in capture.surfaces:
		assert(surface.source is ImageTexture, "Water requires full source quad UVs")
		assert(
			surface.material.get_shader_parameter("water_texture") == capture.viewport.get_texture()
		)
		assert(
			is_equal_approx(
				surface.material.get_shader_parameter("water_camera_x"),
				lab.camera.position.x / 16.0
			)
		)
	for pair: Dictionary in capture.stage_pairs:
		assert(not pair.source.is_water, "Reflection must not read its own in-flight target")
		assert(pair.source != pair.copy and pair.source.transform == pair.copy.transform)
		assert(pair.source.current_sprite == pair.copy.current_sprite)
	lab.player.set_physics_process(false)
	lab.player.sprite.play("jump", true)
	lab.player.sprite.advance(0.1)
	lab.player.position += Vector2(-42, -33)
	lab.player.projectile.position = Vector2(20, -40)
	lab.player.projectile.show()
	capture._process(0.0)
	for pair: Dictionary in capture.actor_pairs:
		assert(pair.copy.texture == pair.source.texture)
		assert(pair.copy.transform == pair.source.global_transform)
		assert(pair.copy.visible == pair.source.is_visible_in_tree())
	# Hit blinking also affects the source renderer tint; the reflection must
	# not leave an opaque duplicate behind while the character fades.
	lab.player.story_mode = true
	lab.player.respawn()
	lab.player.action_state = ""
	assert(lab.player.receive_damage(1.0))
	capture._process(0.0)
	assert(is_equal_approx(capture.actor_pairs[0].copy.modulate.a, 0.1))
	lab.player.damage.advance(0.1)
	capture._process(0.0)
	assert(capture.actor_pairs[0].copy.modulate.a == 1.0)
	var old_capture: WeakRef = weakref(capture)
	lab.load_level(0)
	await process_frame
	assert(lab.water_capture == null and old_capture.get_ref() == null)
	lab.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _gpu_pixels(source)
	print("WATER_PROBE_PASS")
	quit()


func _gpu_pixels(source: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != &"gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rectangle := ColorRect.new()
	rectangle.size = Vector2(viewport.size)
	viewport.add_child(rectangle)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	# Encode UV displacement around mid-gray for accurate readback on both
	# RGBA8 and float targets; the production include supplies all water math.
	shader.code = """shader_type canvas_item;
render_mode unshaded;
#include "res://Samples/ArtDirection/Shaders/OriginalWaterUV.gdshaderinc"
void fragment() {
    vec2 input_uv = vec2(UV.x, 1.0 - UV.y);
    vec2 output_uv = original_water_uv(input_uv, TIME);
    COLOR = vec4((output_uv - UV) * 20.0 + vec2(0.5), 0.0, 1.0);
}
"""
	material.shader = shader
	Water.configure(material, viewport.use_hdr_2d)
	rectangle.material = material
	# 2 repeats at 320x180 choose native mip 3: round(log2(1024/180)).
	var normal_texture: Texture2D = load(Assets.ROOT + source.normal.mips[3].path)
	normal = normal_texture.get_image()
	for camera_x in [-137.5, 0.0]:
		for time in [0.0, 0.125, 1.75]:
			material.set_shader_parameter("water_camera_x", camera_x)
			material.set_shader_parameter("water_time", time)
			await _render_frames()
			var actual := viewport.get_texture().get_image()
			var largest := 0.0
			for y in range(2, 180, 11):
				for x in range(3, 320, 13):
					var uv := Vector2((x + 0.5) / 320.0, 1.0 - (y + 0.5) / 180.0)
					var expected := _source_uv(uv, time, camera_x, source.material)
					var pixel := actual.get_pixel(x, y)
					var result := (
						Vector2(pixel.r - 0.5, pixel.g - 0.5) / 20.0 + Vector2(uv.x, 1.0 - uv.y)
					)
					largest = maxf(largest, result.distance_to(expected))
			print("WATER_UV_GPU camera=", camera_x, " time=", time, " max_error=", largest)
			assert(largest < 0.00035, "Water UV differs from source instruction oracle")

	# Check the real water output, including native center-double-counting and
	# sRGB decoding, without depending on scene content or stochastic wave phase.
	material.shader = Water.WaterShader
	Water.configure(material, viewport.use_hdr_2d)
	var color := Color(0.5, 0.25, 0.75, 1.0)
	var texture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	texture.fill(color)
	material.set_shader_parameter("water_texture", ImageTexture.create_from_image(texture))
	rectangle.modulate = Color(0.2, 0.3, 0.4, 0.5)
	await _render_frames()
	var expected := texture.get_pixel(0, 0).srgb_to_linear() * (26.0 / 25.0)
	if not viewport.use_hdr_2d:
		expected = expected.linear_to_srgb()
	var actual := viewport.get_texture().get_image().get_pixel(160, 90)
	assert(
		(
			Vector3(actual.r, actual.g, actual.b).distance_to(
				Vector3(expected.r, expected.g, expected.b)
			)
			< 0.012
		)
	)
	assert(actual.a > 0.99, "Source water ignores renderer alpha")
	viewport.queue_free()
	await process_frame


func _render_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw


func _source_uv(uv: Vector2, time: float, camera_x: float, source: Dictionary) -> Vector2:
	var scroll := _f32(_f32(time * source._Speed) + camera_x * 0.01)
	var noise_uv := uv * float(source._Tilling) + Vector2.ONE * scroll
	var color := _noise_sample(Vector2(noise_uv.x, 1.0 - noise_uv.y))
	var direction := Vector2(color.r * color.a, color.g) * 2.0 - Vector2.ONE
	var result := Vector2(uv.x, 1.0 - uv.y) + direction * float(source._Strength)
	var first := _voronoi(
		Vector2(uv.x * 0.5 + scroll, uv.y * 5.0 + 0.5) * 50.0,
		time * float(source._SurfaceSpeed) + 123.0
	)
	var second := _voronoi(
		(uv * Vector2(1.0, 34.959999084472656) + Vector2(0, 1.0299999713897705)) * 10.0, time
	)
	var edge := clampf((uv.y - 1.0010000467300415) * -48.559669494628906, 0.0, 1.0)
	edge = edge * edge * (3.0 - 2.0 * edge)
	return result + Vector2.ONE * ((first * second - 0.5) * 0.01 * edge)


func _noise_sample(uv: Vector2) -> Color:
	var point := uv * Vector2(normal.get_size()) - Vector2.ONE * 0.5
	var base := Vector2i(point.floor())
	var fraction := point - point.floor()
	return _texel(base).lerp(_texel(base + Vector2i.RIGHT), fraction.x).lerp(
		_texel(base + Vector2i.DOWN).lerp(_texel(base + Vector2i.ONE), fraction.x), fraction.y
	)


func _texel(point: Vector2i) -> Color:
	return normal.get_pixel(
		posmod(point.x, normal.get_width()), posmod(point.y, normal.get_height())
	)


func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


func _voronoi(coordinate: Vector2, angle: float) -> float:
	var cell := Vector2i(coordinate.floor())
	var fraction := coordinate - coordinate.floor()
	var nearest := 8.0
	for y in range(-1, 2):
		for x in range(-1, 2):
			var seed := ((cell.y + y) & 0xffffffff) ^ 0x41c64e6d
			var mixed := (((cell.x + x + seed) & 0xffffffff) * seed) & 0xffffffff
			mixed ^= mixed >> 5
			var product := (mixed * 0x27d4eb2d) & 0xffffffff
			var hash_x := (seed ^ ((product << 3) & 0xffffffff)) >> 8
			var hash_y := product >> 8
			var phase_x := _f32(_f32(float(hash_x) * angle) * 0.00000005960465188081798)
			var phase_y := _f32(_f32(float(hash_y) * angle) * 0.00000005960465188081798)
			var delta := (
				Vector2(x, y)
				+ Vector2(sin(phase_x), cos(phase_y)) * 0.5
				- fraction
				+ Vector2.ONE * 0.5
			)
			nearest = minf(nearest, delta.length())
	return nearest
