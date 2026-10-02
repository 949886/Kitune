extends SceneTree
## Source particle shader selection and GPU/CPU comparison of the authored light mask.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Lighting = preload("res://Samples/ArtDirection/Runtime/OriginalLighting.gd")
const SceneProjection = preload("res://Samples/ArtDirection/Runtime/OriginalSceneProjection.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
	var effect: Node = lab.stage.spawn_effect("Eff_RifleMan_Shot", lab.player.position, 0.0)
	var spark: Node = effect.emitters[0]
	var smoke: Node = effect.emitters[1]
	var fire: Node = effect.emitters[2]
	assert(spark.shared_material.shader.resource_path.ends_with("OriginalGlow.gdshader"))
	for emitter: Node in [smoke, fire]:
		assert(emitter.shared_material.shader.resource_path.ends_with("OriginalLit.gdshader"))
		var layer: Dictionary = lab.stage.lighting.layers[int(
			emitter.data.renderer.m_SortingLayerID
		)]
		assert(emitter.shared_material.get_shader_parameter("light_data") == layer.texture)
		assert(emitter.shared_material.get_shader_parameter("glow_affects_light"))
	assert(not smoke.shared_material.get_shader_parameter("lighting_mask_textured"))
	assert(fire.shared_material.get_shader_parameter("lighting_mask_textured"))
	var source: Dictionary = fire.data.material
	assert(source.shader_proof.program_index == 861 and source.shader_proof.parameter_index == 600)
	var mask: Texture2D = fire.shared_material.get_shader_parameter("lighting_mask_texture")
	var pixels := mask.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pixels.get_data())
	assert(hash.finish().hex_encode() == source.lighting_mask_texture.pixel_sha256)
	lab.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _verify_gpu(source, pixels)
	print("PARTICLE_LIGHTING_PASS")
	quit()


func _verify_gpu(source: Dictionary, mask: Image) -> void:
	# Each fixture pixel maps to exactly one source mask texel, avoiding an
	# accidental test of Godot's filtering instead of the native point sampler.
	var viewport := SubViewport.new()
	viewport.size = mask.get_size()
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var projection := SceneProjection.new()
	viewport.add_child(projection)
	projection.configure(Assets.read_json(Assets.ROOT + "camera.json"))
	var lighting := Lighting.new()
	viewport.add_child(lighting)
	lighting.configure({"lights": []}, projection)
	lighting.exposure_screen.hide()
	var texel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	texel.fill(Color(64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(texel)
	sprite.position = Vector2(viewport.size) * 0.5
	sprite.scale = Vector2(viewport.size)
	viewport.add_child(sprite)
	lighting.apply_source(sprite, source, -232159969, "particle-mask-fixture")
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("ambient", Vector3(0.1, 0.1, 0.1))
	material.set_shader_parameter("light_count", 0)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := viewport.get_texture().get_image()
	var sample := Color(64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0).srgb_to_linear()
	var glow := Assets.color(source.glow_color).srgb_to_linear()
	var tint := Assets.color(source.color).srgb_to_linear()
	var surface := (
		Vector3(sample.r, sample.g, sample.b)
		* (
			Vector3.ONE * float(source.glow_global)
			+ Vector3(glow.r, glow.g, glow.b) * float(source.glow)
		)
		* Vector3(tint.r, tint.g, tint.b)
	)
	var maximum_error := 0.0
	var changed := 0
	for y in range(0, mask.get_height(), 3):
		for x in range(0, mask.get_width(), 7):
			var color := mask.get_pixel(x, y).srgb_to_linear()
			var mask_value := Vector3(color.r, color.g, color.b) * float(source.lit_amount)
			var weight := (mask_value.clamp(Vector3.ZERO, Vector3.ONE) * 2.0 - surface).clamp(
				Vector3.ZERO, Vector3.ONE
			)
			var expected := surface * (Vector3.ONE - weight * 0.9)
			var actual := output.get_pixel(x, y)
			if not lighting.linear_framebuffer:
				actual = actual.srgb_to_linear()
			var difference := Vector3(actual.r, actual.g, actual.b) - expected
			# LDR renderers clip HDR red; green and blue still exercise the mask.
			var error := maxf(absf(difference.y), absf(difference.z))
			if lighting.linear_framebuffer:
				error = maxf(error, absf(difference.x))
			maximum_error = maxf(maximum_error, error)
			if weight.z > 0.05:
				changed += 1
	assert(changed > 20, "Fixture must exercise nonuniform mask pixels, not only its black border")
	assert(maximum_error < 0.008, "Source particle light-mask formula diverged: %f" % maximum_error)
	print("PARTICLE_LIGHTING_GPU_PASS error=", maximum_error, " affected=", changed)
	viewport.queue_free()
	await process_frame
