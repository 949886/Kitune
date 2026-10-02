extends SceneTree
## Actual throw/collision lifecycle, original pixels, distance particles and snapshot ghosts.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Afterimages = preload("res://Samples/ArtDirection/Runtime/InariKunaiAfterimages.gd")
const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")

var lab: Node
var effects: Array[Node2D] = []


func _initialize() -> void:
	call_deferred("run")


func afterimages(flight: Node) -> Node:
	for child: Node in flight.get_children():
		if child is Afterimages:
			return child
	assert(false, "Kunai child trail must include its native AfterimageEmitter")
	return null


func check_pixels(effect: Node) -> void:
	for emitter: Node in effect.emitters:
		var pixels: Image = emitter.texture.get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == emitter.data.texture.pixel_sha256)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(1)
	await process_frame
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node = lab.player
	player.position = Vector2(-20000, -20000)
	lab.stage.effect_started.connect(func(effect: Node2D): effects.append(effect))
	player.throw_projectile(Vector2.RIGHT)
	var flight: Node = player.projectile_flight
	var ghosts: Node = afterimages(flight)
	assert(flight.effect_key == "KunaiFlight" and flight.emitters.size() == 1)
	check_pixels(flight)
	var emitter: Node = flight.emitters[0]
	assert(emitter.system.looping and int(emitter.system.moveWithTransform) == 1)
	assert(emitter.system.EmissionModule.rateOverTime.scalar == 0.0)
	var origin: Vector2 = player.projectile.global_position
	lab.stage.combat_clock.stop_frames(60, 1.0 / 60.0)
	for tick in 12:
		player._update_projectile(1.0 / 60.0)
		flight._process(0.0)
		emitter.advance(1.0 / 60.0)
		ghosts.advance(1.0 / 60.0)
	var units: float = player.projectile.global_position.distance_to(origin) / player.units
	assert(emitter.emitted == floori(units * 3.0))
	assert(ghosts.ghosts.size() == 6, "At 60 Hz, native 0.02 interval emits every two updates")
	var latest: Sprite2D = ghosts.ghosts.back()
	var expected := 0.7 * SourceCurve.evaluate(latest.source.alphaOverLife, (1.0 / 60.0) / 0.2)
	assert(absf(latest.modulate.a - expected) < 0.00001)
	assert(latest.global_transform == player.projectile.global_transform)
	assert(latest.z_index > player.projectile.z_index)
	assert(not latest.material.get_shader_parameter("hit_enabled"))
	var snapshot: Transform2D = latest.global_transform
	# No movement means no new ghost even after its timer has elapsed.
	ghosts.advance(1.0 / 60.0)
	assert(ghosts.ghosts.size() == 6 and latest.global_transform == snapshot)
	expected = 0.15 * SourceCurve.evaluate(latest.source.alphaOverLife, (2.0 / 60.0) / 0.2)
	assert(absf(latest.modulate.a - expected) < 0.00001)
	lab.water_capture.projectiles.sync()
	lab.water_capture.particles.sync()
	var mirror: Sprite2D = lab.water_capture.projectiles.kunai_pairs[latest.get_instance_id()].copy
	assert(
		mirror.global_transform == latest.global_transform and mirror.modulate == latest.modulate
	)
	assert(mirror.material != latest.material)
	if DisplayServer.get_name() != "headless":
		await verify_gpu(player.projectile.global_position)
	# Replacing the active blade transfers its existing particle and ghost history.
	var old_particle: Sprite2D = emitter.particles[0].visual
	player.throw_projectile(Vector2.LEFT)
	assert(player.projectile_flight != flight)
	assert(flight.follow_actor != player.projectile)
	assert(flight.follow_actor.flight == flight and old_particle == emitter.particles[0].visual)
	assert(ghosts.ghosts.back() == latest)
	flight.follow_actor.finish()
	lab.water_capture.projectiles.sync()
	assert(not mirror.visible and ghosts.ghosts.is_empty())
	# Real collision removes the whole child trail, including already emitted ghosts.
	player._clear_projectile()
	player.throw_projectile(Vector2.RIGHT)
	flight = player.projectile_flight
	var wall := make_wall(player.projectile.global_position + Vector2(50, 0), true)
	await physics_frame
	player._update_projectile(0.1)
	assert(player.projectile_stuck and not flight.visible and flight.is_queued_for_deletion())
	var stick: Node = effects.back()
	assert(stick.effect_key == "Eff_Player_KunaiStick" and stick.emitters.size() == 2)
	assert(stick.global_position == player.projectile.global_position)
	assert(stick.global_rotation == player.projectile.global_rotation)
	check_pixels(stick)
	for item: Node in stick.emitters:
		item.advance(0.01)
	# Bursts request 15/30, but each native emitter caps itself at 10 particles.
	assert(stick.emitters[0].emitted == 10 and stick.emitters[1].emitted == 10)
	if DisplayServer.get_name() != "headless":
		await verify_impact_gpu(stick)
	var count := effects.size()
	player._retire_projectile()
	assert(effects.size() == count, "FadeOut must not play the destruction burst")
	# Hard-wall destruction uses contact position and prefab rotation, not throw angle.
	wall.set_meta("climbable", false)
	wall.set_meta("source_layer", "HardWall")
	player.throw_projectile(Vector2(1.0, 0.2).normalized())
	player._update_projectile(0.1)
	var destroy: Node = effects.back()
	assert(not player.projectile_active and destroy.effect_key == "Eff_Player_KunaiDestroy")
	assert(destroy.emitters.size() == 4 and destroy.rotation == 0.0)
	assert(absf(destroy.global_position.x - (wall.position.x - 5.0)) < 0.01)
	check_pixels(destroy)
	for item: Node in destroy.emitters:
		item.advance(0.01)
	for index in 4:
		assert(destroy.emitters[index].emitted == [30, 1, 1, 30][index])
	if DisplayServer.get_name() != "headless":
		stick.hide()
		await verify_impact_gpu(destroy)
	# Raw Pop calls do not register with the combat time domain.
	lab.stage.combat_clock.stop_frames(60, 1.0 / 60.0)
	var before: float = destroy.emitters[0].clock
	destroy.emitters[0].advance(0.05)
	assert(is_equal_approx(destroy.emitters[0].clock - before, 0.055))
	var old_capture: WeakRef = weakref(lab.water_capture)
	lab.load_level(0)
	await process_frame
	assert(old_capture.get_ref() == null)
	lab.queue_free()
	await process_frame
	print("KUNAI_EFFECTS_PASS")
	quit()


func make_wall(point: Vector2, climbable: bool) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.process_mode = Node.PROCESS_MODE_ALWAYS
	wall.collision_layer = Collision.PROJECTILE_SURFACE
	wall.set_meta("climbable", climbable)
	wall.set_meta("source_layer", "Ground" if climbable else "HardWall")
	wall.position = point
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 100)
	shape.shape = rectangle
	wall.add_child(shape)
	lab.stage.add_child(wall)
	return wall


func verify_gpu(point: Vector2) -> void:
	var capture: Node = lab.water_capture
	for collection: Array in [
		capture.stage_pairs, capture.actor_pairs, capture.line_pairs, capture.marker_pairs
	]:
		for entry: Dictionary in collection:
			entry.copy.hide()
	capture.camera.position = point - Vector2(120, 0)
	capture.camera.force_update_scroll()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = capture.viewport.get_texture().get_image()
	assert(
		image.get_used_rect().size.x > 100,
		"Native particles and frozen ghosts must span the flight path"
	)
	image.save_png("res://tmp/art-direction/inari_kunai_effects_water.png")
	print("KUNAI_EFFECTS_GPU bounds=", image.get_used_rect())


func verify_impact_gpu(effect: Node2D) -> void:
	var capture: Node = lab.water_capture
	capture.projectiles.sync()
	capture.projectiles.hide()
	capture.particles.sync()
	capture.camera.position = effect.global_position
	capture.camera.force_update_scroll()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = capture.viewport.get_texture().get_image()
	assert(image.get_used_rect().size.x > 3 and image.get_used_rect().size.y > 3)
	image.save_png("res://tmp/art-direction/" + effect.effect_key + "_water.png")
	print("KUNAI_IMPACT_GPU ", effect.effect_key, " bounds=", image.get_used_rect())
