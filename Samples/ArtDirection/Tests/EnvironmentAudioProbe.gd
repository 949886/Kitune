extends SceneTree
## Native source geometry, actual actor overlaps and persistent mixer ownership.
var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await frames(8)
	var mixer: Node = lab.environment_audio
	assert(mixer.initialized and mixer.failures.is_empty())
	assert(lab.stage.data.source == "level15")
	assert(lab.environment_zones.zones.size() == mixer.document.levels.level15.size())
	# Freeze movement only; the real collision body still participates in overlaps.
	lab.player.set_physics_process(false)
	var destination: Area2D
	for zone: Area2D in lab.environment_zones.zones:
		assert(zone.transform == zone.settings.source_transform)
		if zone.get_meta("source_component") == 11051: destination = zone
	assert(destination != null)
	lab.player.global_position = Vector2(-100000, -100000)
	await frames(4)
	var calls: int = destination.calls
	lab.player.global_position = destination.to_global(destination.settings.trigger_offset)
	await frames(4)
	assert(destination.calls > calls)
	for key: String in destination.settings.parameters:
		assert(absf(mixer.parameter("ambient", key).x - float(destination.settings.parameters[key])) < 0.00001)
	var old_zone: WeakRef = weakref(destination)
	var runtime: WeakRef = weakref(mixer.native)
	lab.load_level(2)
	await frames(12)
	assert(old_zone.get_ref() == null and lab.environment_audio == mixer)
	assert(runtime.get_ref() == mixer.native and mixer.failures.is_empty())
	assert(lab.environment_zones.zones.size() == mixer.document.levels[lab.stage.data.source].size())
	var entries := 0
	for zone: Area2D in lab.environment_zones.zones: entries += zone.calls
	assert(entries > 0) # The actual tutorial spawn starts inside authored zones.
	lab.queue_free()
	await frames(4)
	assert(runtime.get_ref() == null)
	print("NATIVE_ENVIRONMENT_AUDIO_PASS")
	quit()
