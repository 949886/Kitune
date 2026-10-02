extends SceneTree
## Original bomb animation dependencies and the actual pooled steam explosion.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const PARTICLES := "res://Samples/ArtDirection/Original/INARI/Particles/"


func _initialize() -> void:
	call_deferred("run")


func pixel_hash(pixels: Image) -> String:
	pixels.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pixels.get_data())
	return hash.finish().hex_encode()


func run() -> void:
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "bomb_presentation.json")
	assert(evidence.actors.size() == 2 and evidence.added_sprite_sha256.size() == 38)
	for key: String in evidence.added_sprite_sha256:
		var texture: AtlasTexture = Assets.texture(key)
		assert(pixel_hash(texture.get_image()) == evidence.added_sprite_sha256[key])
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	var bombs: Array[Node] = []
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if enemy.data.kind == "EnemyBombMan":
			bombs.append(enemy)
	assert(bombs.size() == 2)
	for bomb: Node in bombs:
		bomb.motion_animation.set_process(false)
		bomb.play_combat_motion("AttackReady")
		assert(is_equal_approx(bomb.motion_duration, 5.0 / 12.0))
		var visual: Node = bomb.visuals[bomb.data.primary_visual]
		var first = visual.current_sprite
		bomb.motion_animation.advance(0.3)
		bomb.motion_animation.advance(0.0)
		assert(visual.current_sprite != first)
		bomb.play_combat_motion("AttackConfirm")
		assert(is_equal_approx(bomb.motion_duration, 19.0 / 12.0))
		first = visual.current_sprite
		bomb.motion_animation.advance(0.4)
		bomb.motion_animation.advance(0.0)
		assert(visual.current_sprite != first)
		bomb.play_combat_motion("RunReady")
		assert(is_equal_approx(bomb.motion_duration, 1.0 / 30.0))
		bomb.play_combat_motion("Chase")
		assert(is_equal_approx(bomb.motion_duration, 11.0 / 24.0))
		assert(not bomb.data.combat_animations.has("Attack:0"))
	var effect: Node = lab.stage.spawn_effect("Eff_Enemy_BamBoom_Explosion", bombs[0].position, 0.0)
	effect.set_process(false)
	assert(effect.emitters.size() == 8)
	var steam: Node
	var wave: Node
	for emitter: Node in effect.emitters:
		emitter.set_process(false)
		assert(pixel_hash(emitter.texture.get_image()) == emitter.data.texture.pixel_sha256)
		if emitter.system.ShapeModule.enabled:
			var shape: Dictionary = emitter._shape()
			assert(is_zero_approx(shape.position.z) and is_zero_approx(shape.direction.z))
			assert(
				is_equal_approx(shape.position.length(), emitter.system.ShapeModule.radius.value)
			)
			assert(shape.position.normalized().is_equal_approx(shape.direction))
		assert(
			emitter.pose.origin.length() < 3.0, "Pooled effect must discard its authored root pose"
		)
		if emitter.data.name == "boomsteam":
			steam = emitter
		elif emitter.data.name == "wave":
			wave = emitter
	assert(steam != null and wave != null)
	assert(steam.shared_material.get_shader_parameter("inner_outline_enabled"))
	assert(steam.data.material.shader_proof.keywords == ["GLOW_ON", "INNEROUTLINE_ON"])
	for frame in 6:
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)
	assert(steam.emitted == 0 and wave.emitted == 0)
	for frame in 2:
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)
	assert(steam.emitted == 0 and wave.emitted == 1)
	for frame in 2:
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)
	assert(steam.emitted == 1)
	var first_frame: int = steam.particles[0].visual.frame
	for frame in 8:
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)
	assert(steam.particles[0].visual.frame > first_frame)
	var source: Dictionary = steam.data.material
	var texture: Texture2D = steam.texture
	if DisplayServer.get_name() != "headless":
		lab.camera_rig.set_process(false)
		lab.camera.position = effect.position + Vector2(0, -32)
		lab.camera.zoom = Vector2(1.5, 1.5)
		lab.camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bomb_explosion.png")
	for frame in 420:
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)
	assert(effect.emitters.all(func(emitter: Node): return emitter.particles.is_empty()))
	effect._process(0.0)
	await process_frame
	assert(not is_instance_valid(effect))
	lab.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await verify_outline(source, texture)
		# The shipped outline color is black. A colored fixture also exercises
		# the contribution itself instead of only checking the disabled result.
		var colored_source := source.duplicate(true)
		colored_source.inner_outline_color = [0.8, 0.35, 0.15, 1.0]
		await verify_outline(colored_source, texture)
	print("BOMB_PRESENTATION_PASS")
	quit()


func rgb(color: Color) -> Vector3:
	var linear := color.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b)


func verify_outline(source: Dictionary, texture: Texture2D) -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return  # Native HDR emission cannot be compared after LDR clipping.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.world_2d = World2D.new()
	viewport.use_hdr_2d = true
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
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = false
	var origin := Vector2i(1024, 1024)
	sprite.region_rect = Rect2(origin, viewport.size)
	sprite.modulate.a = 0.5
	var material := ShaderMaterial.new()
	material.shader = Glow
	MaterialSettings.configure(material, source, true)
	sprite.material = material
	viewport.add_child(sprite)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := viewport.get_texture().get_image()
	var pixels := texture.get_image()
	var outline := rgb(Assets.color(source.inner_outline_color))
	var glow := rgb(Assets.color(source.glow_color))
	var tint := rgb(Assets.color(source.color))
	var checked := 0
	var maximum_error := 0.0
	for y in range(2, 254):
		for x in range(2, 254):
			var point := origin + Vector2i(x, y)
			var pixel := pixels.get_pixelv(point)
			var alpha := pixel.a * 0.5
			var dx := (
				rgb(pixels.get_pixelv(point + Vector2i.RIGHT))
				- rgb(pixels.get_pixelv(point + Vector2i.LEFT))
			)
			var dy := (
				rgb(pixels.get_pixelv(point + Vector2i.DOWN))
				- rgb(pixels.get_pixelv(point + Vector2i.UP))
			)
			var edge := (
				((dx.abs() + dy.abs()) * 0.5 * alpha * float(source.floats._InnerOutlineAlpha))
				. length()
			)
			var surface := rgb(pixel) + outline * edge * float(source.floats._InnerOutlineGlow)
			surface *= (
				Vector3.ONE * float(source.glow_global) + glow * alpha * alpha * float(source.glow)
			)
			surface *= tint * alpha * float(source.alpha) * float(source.color[3])
			var actual := output.get_pixel(x, y)
			var difference := (Vector3(actual.r, actual.g, actual.b) - surface).abs()
			var relative := difference / (Vector3.ONE + surface.abs())
			maximum_error = maxf(maximum_error, maxf(relative.x, maxf(relative.y, relative.z)))
			if edge > 0.001:
				checked += 1
	print("BOMB_OUTLINE_COMPARE samples=", checked, " relative_error=", maximum_error)
	assert(checked > 100, "The source frame must exercise RGB edges")
	assert(maximum_error < 0.004, "Inner-outline GPU formula mismatch: " + str(maximum_error))
	print("BOMB_OUTLINE_GPU_PASS samples=", checked, " relative_error=", maximum_error)
	viewport.queue_free()
	await process_frame
