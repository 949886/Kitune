extends SceneTree
## Native outline restart/gate, raw pool particle lifetime and real combat callers.

var lab: Node
var spawned: Array[Node2D] = []


func _initialize() -> void:
	call_deferred("run")


func track(effect: Node2D) -> void:
	if effect.effect_key == "Eff_Accel":
		spawned.append(effect)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var player: Node = lab.player
	player.set_physics_process(false)
	var feedback: Node = player.stamina_feedback
	feedback.set_process(false)
	lab.stage.effect_started.connect(track)
	var material: ShaderMaterial = player.sprite.material
	feedback.trigger()
	assert(spawned.size() == 1 and feedback.active)
	assert(material.get_shader_parameter("inner_outline_alpha") == 0.0)
	feedback.advance(0.1)
	assert(absf(material.get_shader_parameter("inner_outline_alpha") - 0.5625) < 0.00001)
	lab.stage.combat_clock.stop_frames(60, 1.0 / 60.0)
	feedback.advance(0.1)
	assert(absf(material.get_shader_parameter("inner_outline_alpha") - 0.25) < 0.00001)
	feedback.trigger()
	assert(spawned.size() == 2 and material.get_shader_parameter("inner_outline_alpha") > 0.0)
	feedback.advance(0.1)
	assert(absf(material.get_shader_parameter("inner_outline_alpha") - 0.5625) < 0.00001)
	feedback.trigger(0, 1)
	feedback.advance(1.0)
	assert(not feedback.active and spawned.size() == 2)
	assert(absf(material.get_shader_parameter("inner_outline_alpha") - 0.5625) < 0.00001)
	lab.water_capture._process(0.0)
	var mirror: Sprite2D
	for pair: Dictionary in lab.water_capture.actor_pairs:
		if pair.source == player.sprite:
			mirror = pair.copy
	assert(mirror != null and mirror.material != material)
	assert(
		(
			mirror.material.get_shader_parameter("inner_outline_alpha")
			== material.get_shader_parameter("inner_outline_alpha")
		)
	)
	if DisplayServer.get_name() != "headless":
		await verify_outline_gpu(player.sprite)
	feedback.trigger(1, 1)
	feedback.advance(0.4)
	assert(not feedback.active and material.get_shader_parameter("inner_outline_alpha") == 0.0)
	var effect: Node = spawned.back()
	assert(effect.follow_actor == feedback.anchor and effect.emitters.size() == 1)
	var emitter: Node = effect.emitters[0]
	assert(emitter.time_scale_override < 0.0)
	var pixels: Image = emitter.texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pixels.get_data())
	assert(hash.finish().hex_encode() == emitter.data.texture.pixel_sha256)
	emitter.advance(0.01)
	assert(emitter.emitted == 1 and emitter.particles[0].local)
	var before: Vector2 = emitter.particles[0].visual.global_position
	player.position.x += 32.0
	effect._process(0.0)
	emitter._update(emitter.particles[0], 0.0)
	assert(emitter.particles[0].visual.global_position.is_equal_approx(before + Vector2(32, 0)))
	var clock: float = emitter.clock
	emitter.advance(0.05)
	assert(is_equal_approx(emitter.clock - clock, 0.05))
	if DisplayServer.get_name() != "headless":
		await verify_effect_gpu(effect)
	# Gameplay calls: ordinary nonlethal hit, heavy hit, player kill, duplicate kill.
	lab.load_level(0)
	await process_frame
	spawned.clear()
	lab.stage.effect_started.connect(track)
	player = lab.player
	player.set_physics_process(false)
	player.stamina_feedback.set_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	var target: Node = lab.stage.enemies[0]
	target.position = Vector2(-20000, -20000)
	player.position = target.position - player.body_shape.position + Vector2(-30, 0)
	target.data.invincible = true
	await physics_frame
	await process_frame
	var check := {"AttackRange": {"x": 16, "y": 16}, "AttackOffset": {"x": 0, "y": 0}}
	player._start_attack(0)
	player._deliver_attack(check)
	assert(spawned.is_empty())
	player._start_attack(0, false, true)
	player._deliver_attack(check)
	assert(spawned.size() == 1 and not target.dead, "Heavy feedback count=" + str(spawned.size()))
	target.data.invincible = false
	target.receive_study_hit(
		{"Damage": target.health + 1.0, "source_actor": player, "kind": "probe"}, 0.0
	)
	assert(target.dead and spawned.size() == 2)
	target.receive_study_hit({"Damage": 1.0, "source_actor": player}, 0.0)
	assert(spawned.size() == 2)
	var other: Node = lab.stage.enemies[1]
	other.receive_study_hit(
		{"Damage": other.health + 1.0, "source_actor": other, "kind": "probe"}, 0.0
	)
	assert(other.dead and spawned.size() == 2)
	# A configured nonzero kunai hit retains its player source through attachment.
	var blade_target: Node = lab.stage.enemies[2]
	var damage: float = player.combat.ShurikenDamage
	player.combat.ShurikenDamage = blade_target.health + 1.0
	blade_target.receive_study_kunai(player)
	player.combat.ShurikenDamage = damage
	assert(blade_target.dead and spawned.size() == 3)
	lab.queue_free()
	await process_frame
	print("STAMINA_FEEDBACK_PASS")
	quit()


func verify_outline_gpu(original: Sprite2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = original.texture
	sprite.texture_filter = original.texture_filter
	sprite.position = Vector2(64, 64)
	sprite.scale = Vector2(2, 2)
	sprite.material = original.material.duplicate()
	viewport.add_child(sprite)
	var material: ShaderMaterial = sprite.material
	material.set_shader_parameter("linear_framebuffer", viewport.use_hdr_2d)
	material.set_shader_parameter("light_count", 0)
	material.set_shader_parameter("ambient", Vector3(0.2, 0.2, 0.2))
	await draw_frames()
	var flash: Image = viewport.get_texture().get_image()
	material.set_shader_parameter("inner_outline_alpha", 0.0)
	await draw_frames()
	var plain: Image = viewport.get_texture().get_image()
	var changed := 0
	for y in plain.get_height():
		for x in plain.get_width():
			var a := plain.get_pixel(x, y)
			var b := flash.get_pixel(x, y)
			assert(absf(a.a - b.a) < 0.01)
			if b.r - a.r > 0.1:
				changed += 1
	assert(changed > 20, "Native inner outline must brighten the actual player pixels")
	flash.save_png("res://tmp/art-direction/inari_stamina_outline.png")
	print("STAMINA_FEEDBACK_GPU changed=", changed)
	viewport.queue_free()
	await process_frame


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw


func verify_effect_gpu(effect: Node2D) -> void:
	var capture: Node = lab.water_capture
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	for collection: Array in [
		capture.stage_pairs, capture.actor_pairs, capture.line_pairs, capture.marker_pairs
	]:
		for pair: Dictionary in collection:
			pair.copy.hide()
	capture.projectiles.hide()
	capture.particles.sync()
	for id: int in capture.particles.pairs:
		var original: Node = instance_from_id(id)
		capture.particles.pairs[id].visible = original.get_parent().effect == effect
	capture.camera.position = effect.global_position
	capture.camera.force_update_scroll()
	await draw_frames()
	var image: Image = capture.viewport.get_texture().get_image()
	assert(image.get_used_rect().size.x > 2 and image.get_used_rect().size.y > 2)
	image.save_png("res://tmp/art-direction/inari_stamina_effect_water.png")
	print("STAMINA_EFFECT_GPU bounds=", image.get_used_rect())
	capture.projectiles.show()
	lab.process_mode = Node.PROCESS_MODE_INHERIT
