extends SceneTree
## Actual entry, input, gated travel and disembarkation. The portal must fire
## before physical arrival; animations must remain attached to the moving cabin.
const Workshop = preload("../Examples/ElevatorWorkshop.tscn")
const Elevator = preload("../Devices/Elevator/Elevator.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
const Assets = preload("../Core/Native/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func check_visual_motion(device: Node) -> void:
	var moving_ids: Array = device.platform.source.children.map(func(id): return int(id))
	for visual: Node2D in device.visual_instances:
		var origin := Vector2(visual.data.transform[4], visual.data.transform[5])
		var expected: Vector2 = origin + visual.animation_offset
		if int(visual.data.get("go", visual.data.get("tilemap_go", -1))) in moving_ids:
			expected += device.platform.position
		assert(
			visual.position.distance_to(expected) < 0.06,
			"Animated leaf drifted from its carrier: " + str(visual.data.get("go", -1))
		)


func run() -> void:
	create_timer(50).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	var elevator: Node = workshop.elevator
	var player: CharacterBody2D = workshop.player
	var platform: Node = elevator.platform
	var events: Array[String] = []
	elevator.audio.event_played.connect(func(event): events.append(event))
	await frames(10)
	assert(elevator.visual_instances.size() == 42 and elevator.child_bodies.size() == 3)
	assert(elevator.mechanism.gates.size() == 2 and elevator.ambient_emitters.size() == 1)
	assert(player.is_on_floor() and not elevator.can_interact(player))
	key(KEY_F, true)
	await frames(3)
	key(KEY_F, false)
	assert(not elevator.is_consumed() and platform.stopped)
	key(KEY_D, true)
	for frame in 80:
		await frames(1)
		if elevator.can_interact(player):
			break
	key(KEY_D, false)
	await frames(16)
	assert(elevator.can_interact(player) and not workshop.hint.text.is_empty())
	var button_visual: Node = elevator.visuals_by_go[elevator.document.outline_ids[0]]
	assert(button_visual.material.get_shader_parameter("base_outline_alpha") > 0.99)
	key(KEY_F, true)
	await frames(3)
	key(KEY_F, false)
	assert(elevator.is_consumed() and elevator.are_doors_closed() and workshop.recalls == 1)
	assert(not elevator.can_interact(player) and not platform.stopped)
	assert(events == ["elevator_steam", "elevator"])
	var source_loop_found := false
	for voice in elevator.audio.get_children():
		if voice.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			assert(voice.stream.loop_end == 1296000)
			source_loop_found = true
	assert(source_loop_found)
	for gate: StaticBody2D in elevator.mechanism.gates:
		assert(gate.collision_layer == elevator.solid_layers)
	assert(not elevator.interact(player) and workshop.recalls == 1)
	var start: Vector2 = platform.position
	await frames(60)
	assert(platform.position == start, "Source two-second wait must precede travel")
	# Freeze motion while ordinary wait/effect clocks continue. Closed gates
	# must physically keep the player from walking out of the cabin.
	elevator.set_motion_scale(0)
	key(KEY_A, true)
	await frames(40)
	key(KEY_A, false)
	assert(player.position.x > 575 and platform.position == start)
	key(KEY_D, true)
	await frames(15)
	key(KEY_D, false)
	var emitter: Node = elevator.ambient_emitters[0]
	var emitted_before: int = emitter.emitted
	await frames(90)
	assert(platform.position == start and emitter.animation_active)
	assert(emitter.emitted > emitted_before, "Delayed Steam activation must replay its one-shot")
	await frames(90)
	var emitted_after: int = emitter.emitted
	await frames(15)
	assert(emitter.emitted == emitted_after, "Repeated active samples must not restart emission")
	assert(button_visual.material.get_shader_parameter("base_outline_alpha") < 0.01)
	var offset: Vector2 = player.position - platform.position
	elevator.set_motion_scale(1)
	var exit_seen := false
	for frame in 600:
		await frames(1)
		assert((player.position - platform.position).distance_to(offset) < 0.1)
		check_visual_motion(elevator)
		if (
			frame == 120
			and DisplayServer.get_name() != "headless"
			and not OS.get_environment("INARI_CAPTURE").is_empty()
		):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
		if workshop.exit_requests > 0 and not exit_seen:
			exit_seen = true
			assert(
				(
					platform.arrival_count == 0
					and platform.position.y > elevator.settings.travel_offset.y
				)
			)
		if platform.arrival_count > 0:
			break
	assert(exit_seen and workshop.destination == "level2" and workshop.exit_requests == 1)
	assert(platform.arrival_count == 1 and platform.stopped)
	assert(platform.position.is_equal_approx(elevator.settings.travel_offset))
	assert(elevator.are_doors_closed())
	await frames(6)
	assert(elevator.are_doors_closed())
	await frames(8)
	assert(not elevator.are_doors_closed() and elevator.audio.get_child_count() == 0)
	for gate: StaticBody2D in elevator.mechanism.gates:
		assert(gate.collision_layer == 0)
	key(KEY_D, true)
	await frames(100)
	key(KEY_D, false)
	await frames(3)
	assert(workshop.completed and player.is_on_floor())
	assert(absf(player.position.y - (400 + elevator.settings.travel_offset.y)) < 0.2)
	assert(not elevator.interact(player) and workshop.exit_requests == 1)
	workshop.queue_free()
	await frames(3)
	await transformed_fixture()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(7)
	await frames(3)
	var old: WeakRef = weakref(gallery.exhibit.elevator)
	var old_emitter: WeakRef = weakref(gallery.exhibit.elevator.ambient_emitters[0])
	gallery.select_exhibit(0)
	await frames(3)
	assert(old.get_ref() == null and old_emitter.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_ELEVATOR_PASS")
	quit()


func transformed_fixture() -> void:
	var fixture := Elevator.instantiate()
	fixture.position = Vector2(2000, -2000)
	fixture.rotation = PI / 2
	fixture.scale = Vector2.ONE * 1.5
	fixture.scene_exit_enabled = false
	fixture.solid_layers = 16
	fixture.actor_layers = 32
	fixture.particle_collision_mask = 16
	root.add_child(fixture)
	fixture.platform.set_physics_process(false)
	fixture.mechanism.set_physics_process(false)
	assert(fixture.portal == null)
	var actor := CharacterBody2D.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5
	capsule.height = 20
	shape.shape = capsule
	actor.add_child(shape)
	actor.position = fixture.mechanism.to_global(fixture.mechanism.get_child(0).position)
	root.add_child(actor)
	await frames(4)
	assert(not fixture.can_interact(actor))
	fixture.bind_passenger(actor, shape, func(): return false)
	assert(not fixture.can_interact(actor))
	fixture.bind_passenger(actor, shape)
	await frames(4)
	assert(fixture.can_interact(actor))
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	assert(not fixture.interact(actor))
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	assert(fixture.interact(actor))
	assert(fixture.is_consumed() and fixture.are_doors_closed())
	for index in fixture.mechanism.gates.size():
		var gate: Node2D = fixture.mechanism.gates[index]
		var expected: Transform2D = (
			fixture.global_transform
			* Assets.matrix(fixture.document.elevator.doors[index].transform)
		)
		assert(gate.global_transform.is_equal_approx(expected))
		assert(gate.collision_layer == 16)
	fixture.unbind_passenger()
	assert(fixture.platform.player == null and fixture.mechanism.player == null)
	var voice: WeakRef = weakref(fixture.audio.get_child(0))
	fixture.platform.advance(20)
	assert(fixture.platform.arrival_count == 1 and fixture.are_doors_closed())
	fixture.mechanism._physics_process(fixture.settings.door_release_seconds - 0.001)
	assert(fixture.are_doors_closed())
	fixture.mechanism._physics_process(0.002)
	assert(not fixture.are_doors_closed())
	await frames(3)
	assert(voice.get_ref() == null)
	check_visual_motion(fixture)
	# Verify the particle adapter queries the host's layer instead of the
	# original project's hard-coded particle-surface bit, using a real ray hit.
	var wall := StaticBody2D.new()
	wall.position = Vector2(4000, -2000)
	wall.collision_layer = 16
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(100, 20)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	root.add_child(wall)
	await frames(3)
	var emitter: Node = fixture.ambient_emitters[0]
	var previous := Vector3(4000 / 16.0, 2050 / 16.0, 0)
	var particle := {
		"position": Vector3(4000 / 16.0, 1950 / 16.0, 0),
		"velocity": Vector3(0, -1, 0),
		"local": false
	}
	emitter._collide(particle, previous, Transform3D.IDENTITY)
	assert(particle.velocity.y > 0 and particle.position == previous)
	var independent := Elevator.instantiate()
	independent.position = Vector2(-2000, 2000)
	root.add_child(independent)
	await frames(2)
	assert(not independent.is_consumed() and independent.platform.position == Vector2.ZERO)
	assert(independent.ambient_emitters[0] != emitter)
	independent.queue_free()
	wall.queue_free()
	actor.queue_free()
	fixture.queue_free()
	await frames(3)
