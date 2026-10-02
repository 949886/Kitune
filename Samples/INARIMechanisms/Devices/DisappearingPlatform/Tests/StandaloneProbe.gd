extends SceneTree
## Runs with ONLY the device directory copied into an empty project.
const Platform = preload("../DisappearingPlatform.tscn")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var parent := Node2D.new()
	parent.position = Vector2(310, 220)
	parent.rotation = 0.2
	parent.scale = Vector2.ONE * 1.5
	root.add_child(parent)
	var platform := Platform.instantiate()
	parent.add_child(platform)
	platform.set_physics_process(false)
	var emission: Sprite2D = platform.visuals[platform.record.states[0].alpha.go]
	assert(emission.modulate.a == 0.0)
	assert(platform.activate())
	platform.advance(0.22)
	assert(emission.modulate.a == 1.0)
	platform.advance(0.20)
	assert(emission.modulate.a == 0.0)
	platform.advance(1.4)
	assert(platform.state == platform.State.HIDDEN)
	await process_frame
	assert(platform.shape.disabled)
	platform.advance(1.25)
	await process_frame
	assert(not platform.shape.disabled and platform._animation_index == 3)
	platform.advance(0.3)
	assert(platform._animation_index == 0 and emission.modulate.a == 0.0)
	# Boundaries quantize to physics ticks at all three rates.
	for rate in [30, 60, 120]:
		platform.reset()
		platform.activate()
		var before: int = ceili(platform.disappear_after * rate) - 1
		for frame in before:
			platform.advance(1.0 / rate)
		assert(platform.state == platform.State.COUNTDOWN)
		platform.advance(1.0 / rate)
		assert(platform.state == platform.State.HIDDEN)
	platform.reset()
	await process_frame
	var query := PhysicsRayQueryParameters2D.create(parent.to_global(Vector2(0, -30)), parent.to_global(Vector2(0, 30)), 1)
	await physics_frame
	var hit := root.world_2d.direct_space_state.intersect_ray(query)
	assert(hit.get("collider") == platform.solid)
	assert(hit.position.distance_to(parent.to_global(Vector2.ZERO)) < 0.01)
	parent.queue_free()
	await process_frame
	print("STANDALONE_DISAPPEARING_PLATFORM_PASS")
	quit()
