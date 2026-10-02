extends SceneTree
## Native frames/curves, deferred buff ordering, private materials and cooldown recovery.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var manifest: Dictionary = Assets.read_json(Assets.ROOT + "wind_animation.json")
	assert(manifest.new_frames.size() == 39)
	for key: String in manifest.new_frames:
		var info := Assets.sprite_info(key)
		var pixels := Assets.texture(key).get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		assert(pixels.get_size() == Vector2i(info.size[0], info.size[1]))
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(
			hash.finish().hex_encode() == info.pixel_sha256,
			"Native animation pixels changed during import"
		)
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node = lab.player
	var trigger: Node = lab.stage.wind_triggers[0]
	var animation: Node = lab.stage.wind_animations[0]
	var other: Node = lab.stage.wind_animations[1]
	assert(animation.visual.material != other.visual.material)
	assert(animation.controller.states.size() == 4)
	for clip: Dictionary in animation.controller.states:
		assert(is_equal_approx(clip.speed, 0.4))
	for track: Dictionary in lab.stage.animation.tracks:
		assert(track.node != animation.visual and track.node != other.visual)
	# Constant channels follow streamed and discrete channels in Unity's packed binding list.
	var enter: Dictionary = animation._sample(1, 1.0 / 60.0)
	assert(absf(enter.values.glow_global - 81.5) < 0.001)
	assert(absf(enter.values.glow_amount - 28.4) < 0.001)
	assert(enter.values.glow_tint.r == 1.0 and enter.values.glow_tint.a == 1.0)
	assert(absf(enter.values.glow_tint.g - 0.40620598) < 0.001)
	var initial: String = animation.visual.current_sprite
	animation.advance(0.25)
	assert(animation.visual.current_sprite != initial)
	assert(is_equal_approx(animation.state_time, 0.1))
	player.action_state = "spawn"
	player.wind_buff.reset()
	trigger.enter(player)
	assert(animation.triggers.has("On") and trigger.pending_player != null)
	assert(player.wind_buff.level == 0)
	animation.advance(0.125)
	assert(animation.state == 0 and not animation.transition.is_empty())
	assert(animation.visual.material.get_shader_parameter("glow_global") > 20.0)
	assert(other.visual.material.get_shader_parameter("glow_global") == 1.0)
	if DisplayServer.get_name() != "headless":
		await capture(animation, "flash")
	for frame in 120:
		animation.advance(1.0 / 60.0)
	assert(animation.state == 2 and animation.transition.is_empty())
	assert(player.wind_buff.level == 0, "Visual trigger must not bypass the deferred spawn buff")
	assert(animation.visual.material.get_shader_parameter("glow_amount") == 1.0)
	assert(animation.visual.material.get_shader_parameter("color_change_new_color") == Color.RED)
	if DisplayServer.get_name() != "headless":
		await capture(animation, "cooldown")
	# Start the five-second cooldown only when the original deferred buff starts.
	player.action_state = "idle"
	trigger.advance(0.0)
	assert(player.wind_buff.level == 1 and trigger.cooling)
	trigger.advance(float(trigger.source.cooldown) - 0.01)
	assert(not animation.triggers.has("Off"))
	trigger.advance(0.02)
	assert(animation.triggers.has("Off") and not trigger.cooling)
	animation.advance(0.125)
	assert(int(animation.transition.destination) == 3)
	for frame in 90:
		animation.advance(1.0 / 60.0)
	assert(animation.state == 0 and animation.transition.is_empty())
	assert(
		(
			animation.visual.material.get_shader_parameter("color_change_new_color")
			== animation.defaults.color_change_new_color
		)
	)
	trigger.enter(player)
	animation.advance(0.3)
	assert(animation.state == 1, "Recovered station must activate again")
	var retired: WeakRef = weakref(animation)
	lab.load_level(1)
	await process_frame
	assert(retired.get_ref() == null)
	assert(lab.stage.wind_animations.is_empty())
	lab.queue_free()
	await process_frame
	print("WIND_ANIMATION_PASS")
	quit()


func capture(animation: Node, label: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(viewport.size)
	backdrop.color = Color(0.015, 0.015, 0.02)
	viewport.add_child(backdrop)
	var sprite := Sprite2D.new()
	sprite.texture = animation.visual.source
	sprite.material = animation.visual.material.duplicate()
	sprite.material.set_shader_parameter("linear_framebuffer", viewport.use_hdr_2d)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(128, 128)
	sprite.scale = Vector2(2, 2)
	viewport.add_child(sprite)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var maximum := 0.0
	for y in pixels.get_height():
		for x in pixels.get_width():
			var color := pixels.get_pixel(x, y)
			maximum = maxf(maximum, maxf(color.r, maxf(color.g, color.b)))
	assert(maximum > 0.1, "Animated station must produce visible pixels")
	pixels.save_png("res://tmp/art-direction/inari_wind_" + label + ".png")
	print("WIND_ANIMATION_GPU ", label, " maximum=", maximum)
	viewport.queue_free()
	await process_frame
