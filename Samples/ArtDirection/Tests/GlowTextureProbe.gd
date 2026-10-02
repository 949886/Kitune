extends SceneTree
## Native GLOWTEX adds independent emission with one main-alpha factor.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Settings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
	var effect: Node = lab.stage.spawn_effect("Eff_WeaknessExposure_ver2", lab.player.position, 0.0)
	var emitter: Node = effect.emitters.filter(func(value: Node): return value.data.material.name == "crosslight_5_m 2")[0]
	var source: Dictionary = emitter.data.material
	assert(source.glow_texture == {"default": "white", "constant": [1.0, 1.0, 1.0, 1.0]})
	assert(source.shader_proof.program_index == 872 and source.shader_proof.parameter_index == 611)
	assert(emitter.shared_material.get_shader_parameter("glow_texture_enabled"))
	assert(emitter.shared_material.get_shader_parameter("glow_texture_constant"))
	assert(emitter.shared_material.shader.resource_path.ends_with("OriginalLit.gdshader"))
	var texture: Texture2D = emitter.texture
	lab.queue_free()
	await process_frame
	if (
		DisplayServer.get_name() != "headless"
		and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	):
		await compare(source, texture)
	print("GLOW_TEXTURE_PASS")
	quit()


func compare(source: Dictionary, texture: Texture2D) -> void:
	var pixels := texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var target := SubViewport.new()
	target.size = pixels.get_size()
	target.use_hdr_2d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var background := ColorRect.new()
	background.size = Vector2(target.size)
	background.color = Color.BLACK
	target.add_child(background)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	target.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = Glow
	Settings.configure(material, source, true)
	# Isolate the emission formula; PINCH has a separate native-mask GPU oracle.
	material.set_shader_parameter("pinch_enabled", false)
	sprite.material = material
	var tint := Color(0.6, 0.8, 0.4).srgb_to_linear()
	var glow := Assets.color(source.glow_color).srgb_to_linear()
	for opacity: float in [0.25, 0.75, 1.0]:
		sprite.modulate = Color(0.6, 0.8, 0.4, opacity)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var actual := target.get_texture().get_image()
		var error := 0.0
		var changed := 0
		for y in range(0, pixels.get_height(), 5):
			for x in range(0, pixels.get_width(), 7):
				var main := (
					pixels.get_pixel(x, y).srgb_to_linear() * Color(tint.r, tint.g, tint.b, opacity)
				)
				var base := Vector3(main.r, main.g, main.b) * float(source.glow_global)
				var emission := Vector3(glow.r, glow.g, glow.b) * main.a * float(source.glow)
				# An opaque black backing isolates ordinary source-alpha blending.
				var expected := (base + emission) * main.a
				var pixel := actual.get_pixel(x, y)
				var difference := (Vector3(pixel.r, pixel.g, pixel.b) - expected).abs()
				error = maxf(error, maxf(difference.x, maxf(difference.y, difference.z)))
				if main.a > 0.01 and main.a < 0.8:
					changed += 1
		assert(changed > 10, "Original texture must exercise partial alpha")
		print("GLOW_TEXTURE_GPU opacity=", opacity, " max_error=", error)
		assert(error < 0.006, "Independent emission or alpha order differs from native program")
	target.queue_free()
	await process_frame
