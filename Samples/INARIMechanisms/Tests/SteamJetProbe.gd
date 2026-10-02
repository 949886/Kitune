extends SceneTree
const Showcase = preload("../Examples/SteamJetShowcase.tscn")
const TempleScene = preload("../Devices/SteamJet/SteamJet.tscn")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	var exhibit := Showcase.instantiate()
	root.add_child(exhibit)
	var first: Node = exhibit.devices[0]
	var second: Node = exhibit.devices[1]
	assert(first.emitters.size() == 3 and not first.source.has_authored_damage)
	assert(first.source.source_scene == "level24" and int(first.source.source_go) == 566)
	assert(second.source.source_scene == "level13")
	assert(is_equal_approx(first.rotation, PI))
	# Ready must expose a populated column before the first rendered frame.
	for emitter: Node in first.emitters:
		assert(is_equal_approx(emitter.clock, float(emitter.system.lengthInSec)))
		assert(emitter.emitted > 0 and not emitter.particles.is_empty())
		assert(is_equal_approx(emitter.time_scale_override, float(emitter.system.simulationSpeed)))
	var main: Node = first.emitters[0]
	var clock_before: float = main.clock
	var origin_y: float = first.global_position.y
	assert(main.particles.any(func(p: Dictionary): return p.visual.global_position.y > origin_y + 200.0))
	# Authored fire layer 6/order -500 must render in front of layer 0's nozzle.
	assert(first.sorting.call([6, -500]) > first.sorting.call([0, 10]))
	var original_z: int = main.particles[0].visual.z_index
	exhibit.z_index = 20
	await frames(2)
	assert(main.particles[0].visual.z_index == original_z + 20)
	exhibit.z_index = 0
	clock_before = main.clock
	first.simulation_speed = 0.0
	await frames(30)
	assert(is_equal_approx(main.clock, clock_before))
	first.simulation_speed = 0.5
	for emitter: Node in first.emitters:
		assert(is_equal_approx(emitter.time_scale_override, float(emitter.system.simulationSpeed) * 0.5))
	first.simulation_speed = 1.0
	await frames(180)
	var before: int = first.emitters[0].emitted
	var other_before: int = second.emitters[0].emitted
	first.deactivate()
	await frames(120)
	assert(first.emitters[0].emitted == before)
	assert(second.emitters[0].emitted > other_before)
	first.activate()
	await frames(15)
	assert(first.emitters[0].emitted > before)
	# Disabled intervals must not be replayed as a backlog of new particles.
	var rate: float = first.emitters[0].system.EmissionModule.rateOverTime.scalar
	assert(first.emitters[0].emitted - before <= ceili(rate * 0.3 * main.time_scale_override) + 2)
	# Capture a mature column rather than the just-restarted emission front.
	await frames(240)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		# A populated simulation alone cannot catch particles hidden behind the
		# background. Sample the actual rendered column below the nozzle.
		var origin: Vector2 = first.get_global_transform_with_canvas().origin
		var warm_pixels := 0
		var lit_rows := 0
		var brightest_green := 0.0
		for y in range(int(origin.y) + 40, picture.get_height() - 10):
			var row_lit := false
			for x in range(int(origin.x) - 90, int(origin.x) + 90):
				var color := picture.get_pixel(x, y)
				if color.r > 0.75 and color.g > 0.12 and color.b < color.r * 0.6:
					warm_pixels += 1
					row_lit = true
					brightest_green = maxf(brightest_green, color.g)
			lit_rows += int(row_lit)
		assert(warm_pixels > 2400 and lit_rows > 150 and brightest_green > 0.8)
		print("STEAM_JET_RENDER_CHECK pixels=%d rows=%d green=%.3f" % [warm_pixels, lit_rows, brightest_green])
		if not OS.get_environment("INARI_CAPTURE").is_empty():
			picture.save_png(OS.get_environment("INARI_CAPTURE"))
	var initially_off: Node = TempleScene.instantiate()
	initially_off.emitting = false
	root.add_child(initially_off)
	for emitter: Node in initially_off.emitters:
		assert(emitter.clock == 0.0 and emitter.particles.is_empty())
	initially_off.activate()
	await frames(2)
	assert(initially_off.emitters[0].emitted > 0)
	initially_off.queue_free()
	exhibit.queue_free()
	await frames(2)
	print("STEAM_JET_PROBE_PASS")
	quit()
