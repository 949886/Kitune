extends SceneTree
const Workshop = preload("../Examples/PlatformWorkshop.tscn")
const Platform = preload("../Devices/MovingPlatform/MovingPlatform.tscn")
const Lever = preload("../Devices/Lever/Lever.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var workshop: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func run() -> void:
	root.size = Vector2i(1280, 720)
	workshop = Workshop.instantiate()
	root.add_child(workshop)
	await frames(10)
	var player: CharacterBody2D = workshop.player
	var platform: Node = workshop.platform
	var lever: Node = workshop.lever
	assert(platform.visual_instances.size() == 35)
	assert(platform.mechanism.lights.size() == 2 and platform.mechanism.wheels.size() == 2)
	assert(player.is_on_floor() and platform.mechanism.stopped)
	assert(not lever.receive_hit(64, player))
	key(KEY_D, true)
	await frames(15)
	key(KEY_D, false)
	key(KEY_J, true)
	await frames(1)
	key(KEY_J, false)
	await frames(2)
	assert(lever.mechanism.switched_on and not platform.mechanism.stopped)
	assert(lever.audio.next_variant.has("lever"))
	key(KEY_D, true)
	var boarded := false
	for frame in 70:
		await frames(1)
		if player.position.x > 305 and player.is_on_floor():
			boarded = true
			break
	key(KEY_D, false)
	assert(boarded)
	var offset: Vector2 = player.global_position - platform.mechanism.global_position
	for frame in 200:
		await frames(1)
		assert(
			absf(player.global_position.x - platform.mechanism.global_position.x - offset.x) < 0.5
		)
		if platform.mechanism.arrival_count > 0:
			break
	assert(platform.mechanism.arrival_count == 1)
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	assert(player.position.x > 895 and player.is_on_floor())
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	# A second instance receives its own motion state and copied source geometry.
	var other := Platform.instantiate()
	other.position = Vector2(500, 100)
	workshop.add_child(other)
	await frames(1)
	assert(other.mechanism.arrival_count == 0 and other.mechanism.stopped)
	other.activate()
	await frames(70)
	assert(other.mechanism.position.x > 0.0 and platform.mechanism.arrival_count == 1)
	# Continuous reversal is position-preserving at the moment of input.
	var before: Vector2 = other.mechanism.position
	other.activate()
	other.mechanism.advance(0.0)
	assert(other.mechanism.position.distance_to(before) < 0.001)
	other.set_motion_scale(0)
	await frames(15)
	assert(other.mechanism.position.distance_to(before) < 0.001)
	# Per-instance settings support a single-use lever without mutating defaults.
	var once := Lever.instantiate()
	once.settings = once.settings.duplicate()
	once.settings.single_use = true
	workshop.add_child(once)
	assert(once.receive_hit(4, player))
	assert(not once.receive_hit(8, player))
	assert(not lever.mechanism.consumed)
	await scaled_passenger_and_crush()
	workshop.queue_free()
	await frames(2)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	for index in [1, 0, 1]:
		gallery.select_exhibit(index)
		await frames(3)
		assert(is_instance_valid(gallery.exhibit))
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_PLATFORM_PROBE_PASS")
	quit()


func scaled_passenger_and_crush() -> void:
	# A plain CharacterBody2D with a capsule has none of the original player's
	# fields. This fixture checks coordinate conversion and the public signal.
	var fixture := Platform.instantiate()
	fixture.position = Vector2(1400, 300)
	fixture.scale = Vector2(1.5, 1.5)
	workshop.add_child(fixture)
	fixture.mechanism.set_physics_process(false)
	var actor := CharacterBody2D.new()
	actor.collision_layer = 4
	actor.collision_mask = 1
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8
	capsule.height = 32
	shape.shape = capsule
	shape.position.y = -16
	actor.add_child(shape)
	actor.position = fixture.position + Vector2(0, -48)
	workshop.add_child(actor)
	fixture.bind_passenger(actor, shape)
	await frames(2)
	fixture.activate()
	fixture.mechanism.clock = fixture.mechanism.next_move
	var before: Vector2 = actor.global_position
	var platform_before: Vector2 = fixture.mechanism.global_position
	fixture.mechanism.advance(0.2)
	var actual: Vector2 = actor.global_position - before
	var expected: Vector2 = fixture.mechanism.global_position - platform_before
	assert(actual.distance_to(expected) < 0.001 and actual.x > 0)
	# A horizontal carrier may slide out from under a blocked passenger. The
	# native crushing case is an upward lift pinning the passenger to a ceiling.
	fixture.mechanism.player = null
	var lift := Platform.instantiate()
	lift.settings = lift.settings.duplicate()
	lift.settings.travel_offset = Vector2(0, -96)
	lift.position = Vector2(1700, 300)
	workshop.add_child(lift)
	lift.mechanism.set_physics_process(false)
	actor.position = lift.position + Vector2(0, -32)
	lift.bind_passenger(actor, shape)
	var wall := StaticBody2D.new()
	wall.position = actor.position + Vector2(0, -50)
	var obstacle := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(120, 10)
	obstacle.shape = rectangle
	wall.add_child(obstacle)
	workshop.add_child(wall)
	var crushed: Array[Node] = []
	lift.passenger_crushed.connect(func(body): crushed.append(body))
	await frames(2)
	lift.activate()
	lift.mechanism.clock = lift.mechanism.next_move
	lift.mechanism.advance(0.4)
	assert(crushed == [actor] and is_instance_valid(actor))
