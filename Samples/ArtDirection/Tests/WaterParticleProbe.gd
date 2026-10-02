extends SceneTree
## Exercise actual effect births, LDR light isolation, paused frames and teardown.

const Mirror = preload("res://Samples/ArtDirection/Runtime/OriginalWaterParticles.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	var capture: Node = lab.water_capture
	var mirror: Node = capture.particles
	var effects: Array[Node] = []
	for key in ["Eff_RifleMan_Shot", "Eff_ArrowDestroy", "Eff_PlayerThirdStack"]:
		var effect: Node = lab.stage.spawn_effect(key, capture.camera.position, 0.0)
		effect.set_process(false)
		for emitter: Node in effect.emitters:
			emitter.set_process(false)
			emitter.advance(0.04)
		effects.append(effect)
	mirror.sync()
	assert(mirror.pairs.size() > 10)
	var found_lit := false
	var found_unlit := false
	var found_sheet := false
	var found_shockwave := false
	for effect: Node in effects:
		for emitter: Node in effect.emitters:
			for particle: Dictionary in emitter.particles:
				var original: Sprite2D = particle.visual
				var copy: Sprite2D = mirror.pairs[original.get_instance_id()]
				assert(copy.get_viewport() == capture.viewport)
				assert(copy.texture == original.texture and copy.frame == original.frame)
				assert(copy.global_transform == original.global_transform)
				assert(copy.modulate == original.modulate and copy.z_index == original.z_index)
				assert(copy.material != original.material)
				var shader: String = copy.material.shader.resource_path
				if shader.ends_with("OriginalShockwave.gdshader"):
					found_shockwave = true
					assert(copy.material.get_shader_parameter("age_percent") > 0.0)
					assert(capture.sorting_capture.z_index < copy.z_index)
				else:
					assert(not copy.material.get_shader_parameter("linear_framebuffer"))
				if shader.ends_with("OriginalUnlitParticle.gdshader"):
					found_unlit = true
				if shader.ends_with("OriginalLit.gdshader"):
					found_lit = true
					var id := int(emitter.data.renderer.m_SortingLayerID)
					var water_light: Texture2D = capture.lighting.layers[id].texture
					assert(copy.material.get_shader_parameter("light_data") == water_light)
					assert(water_light != original.material.get_shader_parameter("light_data"))
				if original.hframes * original.vframes > 1:
					found_sheet = true
	assert(found_lit and found_unlit and found_sheet and found_shockwave)

	# A late attachment discovers existing effects without creating new particles.
	var late := Mirror.new()
	capture.viewport.add_child(late)
	late.configure(lab.stage, capture.lighting)
	late.sync()
	assert(late.pairs.size() == mirror.pairs.size())
	late.queue_free()
	await process_frame

	var shock: Node = effects.back().emitters[0]
	var particle: Dictionary = shock.particles[0]
	var copy: Sprite2D = mirror.pairs[particle.visual.get_instance_id()]
	var before: float = particle.age
	effects.back().on_source_time_scale(0.0)
	shock.advance(0.2)
	mirror.sync()
	assert(particle.age == before)
	assert(
		is_equal_approx(copy.material.get_shader_parameter("age_percent"), before / particle.life)
	)
	effects.back().on_source_time_scale(1.0)
	shock.advance(0.1)
	mirror.sync()
	assert(copy.material.get_shader_parameter("age_percent") > before / particle.life)
	particle.visual.hide()
	mirror.sync()
	assert(not copy.visible)
	particle.visual.show()

	if DisplayServer.get_name() != "headless":
		await verify_gpu(lab, capture)

	# Death removes the draw immediately; freeing whole effects also clears tracking.
	shock.advance(1.0)
	mirror.sync()
	assert(not mirror.pairs.has(particle.visual.get_instance_id()))
	assert(not copy.visible)
	for effect: Node in effects:
		effect.queue_free()
	await process_frame
	mirror.sync()
	# The player now owns an always-on ambient trail. Only those particles may remain.
	var ambient: Node = lab.player.wind_trail.trail
	var remaining_ids: Array[int] = []
	for entry: Dictionary in mirror.emitters:
		assert(entry.source.get_ref().effect == ambient)
	for emitter: Node in ambient.emitters:
		for live: Dictionary in emitter.particles:
			remaining_ids.append(live.visual.get_instance_id())
	assert(mirror.pairs.size() == remaining_ids.size())
	for id: int in mirror.pairs:
		assert(id in remaining_ids)
	var old: WeakRef = weakref(mirror)
	lab.load_level(0)
	await process_frame
	assert(old.get_ref() == null and lab.water_capture == null)
	lab.queue_free()
	await process_frame
	print("WATER_PARTICLE_PASS")
	quit()


func verify_gpu(lab: Node, capture: Node) -> void:
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	# Isolate original particle assets in the real water target. No fixture sprites
	# or replacement shader can make a missing production draw pass this check.
	for collection: Array in [
		capture.stage_pairs, capture.actor_pairs, capture.line_pairs, capture.marker_pairs
	]:
		for pair: Dictionary in collection:
			pair.copy.hide()
	# The shockwave has opaque output; hide it so alpha proves textured particles draw.
	for copy: Sprite2D in capture.particles.pairs.values():
		if copy.material.shader.resource_path.ends_with("OriginalShockwave.gdshader"):
			copy.hide()
	await draw_frames()
	var pixels: Image = capture.viewport.get_texture().get_image()
	var covered := 0
	for y in range(0, pixels.get_height(), 2):
		for x in range(0, pixels.get_width(), 2):
			if pixels.get_pixel(x, y).a > 0.01:
				covered += 1
	assert(covered > 20, "Original particles must draw into the independent LDR water target")
	capture.particles.hide()
	await draw_frames()
	var empty: Image = capture.viewport.get_texture().get_image()
	assert(empty.get_used_rect().size == Vector2i.ZERO)
	capture.particles.show()
	capture._process(0.0)
	await draw_frames()
	capture.viewport.get_texture().get_image().save_png(
		"res://tmp/art-direction/inari_water_particles.png"
	)
	print("WATER_PARTICLE_GPU covered=", covered)
	lab.process_mode = Node.PROCESS_MODE_INHERIT


func draw_frames() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
