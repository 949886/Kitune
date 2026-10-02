extends SceneTree
## Real interaction and travel through the source level14 -> level2 connection.
## A separate clock check covers arrival gates because the native scene portal
## interrupts this particular elevator ride before its physical endpoint.

var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func press(action: String, count := 1) -> void:
	var name: String = lab.player.input_action(action)
	Input.action_press(name)
	await frames(count)
	Input.action_release(name)
	await frames(2)


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2, 2)
	await frames(60)
	var player: Node = lab.player
	var elevator: Node = lab.stage.machinery.elevators[0]
	var platform: Node = elevator.targets[0]
	assert(player.is_on_floor() and player.interaction_target == null)
	await press("interact")
	assert(not elevator.consumed and platform.stopped)
	await press("right", 7)
	assert(player.interaction_target == elevator)
	assert(not lab.interaction_hint.text.is_empty())
	# The source interaction explicitly recalls an existing thrown kunai.
	player.throw_projectile(Vector2.UP)
	assert(player.projectile_active)
	player.damage.health = player.damage.maximum - 1
	await press("interact")
	assert(elevator.consumed and elevator.doors_closed and not player.projectile_active)
	assert(player.interaction_target == null)
	for gate: StaticBody2D in elevator.gates:
		assert(gate.collision_layer != 0)
	assert(lab.stage.audio.last_selection.has("elevator_steam"))
	var loop: AudioStreamWAV = lab.stage.audio._choose_stream("elevator")
	assert(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_end > 0)
	var start: Vector2 = platform.position
	await press("interact")
	await frames(60)
	assert(platform.position == start and not platform.stopped)
	var offset: Vector2 = player.position - platform.position
	var previous: WeakRef = weakref(player)
	for frame in 600:
		await frames(1)
		if previous.get_ref() == null:
			break
		assert(not player.dead)
		assert((player.position - platform.position).distance_to(offset) < 0.05)
	assert(previous.get_ref() == null)
	assert(lab.last_scene_transition.from == "level14")
	assert(lab.last_scene_transition.to == "level2")
	player = lab.player
	assert(player.damage.health == player.damage.maximum)
	var arrival: Node = lab.stage.machinery.arrival
	assert(arrival.active and not lab.controls_enabled and not player.can_process())
	var start_height: float = player.position.y
	for frame in 550:
		await frames(1)
		if not arrival.active:
			break
	assert(not arrival.active and lab.completed and lab.controls_enabled)
	assert(player.can_process() and not player.dead)
	assert(absf(start_height - player.position.y - 480.0) < 1.0)
	assert(player.checkpoint_source == arrival.source.name and player.checkpoint_facing == 1.0)
	assert(not lab.transition_cover.visible and lab.transition_phase.is_empty())
	await frames(5)
	var exit_start: float = player.position.x
	await press("right", 70)
	assert(player.position.x > exit_start + 200.0 and not player.dead)
	assert(player.is_on_floor())
	if DisplayServer.get_name() != "headless":
		lab.completion.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/elevator-exit-verified.png"
		)
	# Reload owns cancellation: an obsolete portal cannot replace the new level.
	lab.load_level(2, 2)
	await frames(5)
	var portal: Node = lab.stage.machinery.portals[0]
	lab.player.position = portal.position
	await frames(5)
	assert(lab.transition_phase == "out")
	lab.load_level(0)
	await frames(250)
	assert(lab.stage.data.source == "level15" and lab.transition_phase.is_empty())
	assert(not lab.transition_cover.visible and lab.last_scene_transition.is_empty())
	# Isolate arrival timing from the portal, using the actual imported platform
	# and gates. No artificial 'arrived' signal is emitted by this test.
	lab.load_level(2, 2)
	await frames(60)
	await press("right", 7)
	await press("interact")
	elevator = lab.stage.machinery.elevators[0]
	platform = elevator.targets[0]
	lab.set_controls_enabled(false)
	platform.advance(100.0)
	assert(platform.stopped and platform.arrival_count == 1 and elevator.doors_closed)
	elevator._physics_process(elevator.release_delay - 0.001)
	assert(elevator.doors_closed)
	elevator._physics_process(0.002)
	assert(not elevator.doors_closed and elevator.consumed)
	for gate: StaticBody2D in elevator.gates:
		assert(gate.collision_layer == 0)
	assert(not elevator.interact(lab.player))
	lab.queue_free()
	await frames(2)
	print(
		"ElevatorProbe: PASS — one-use input, cabin carry, portal, arrival Timeline, exit, cancellation and gates"
	)
	quit()
