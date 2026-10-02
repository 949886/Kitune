extends SceneTree
## Exercises real walking and lever hit queries in the copied, renamed package.
const Workshop = preload("../Examples/DoorWorkshop.tscn")
const Door = preload("../Devices/MachineDoor/MachineDoor.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")


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
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(10)
	var door: Node = workshop.door
	var player: CharacterBody2D = workshop.player
	assert(door.visual_instances.size() == 13)
	assert(not door.is_open() and not door.is_passable())
	var native: Node = door.mechanism
	var wall_shape: CollisionShape2D = native.invisible.get_child(0)
	var half_width: float = wall_shape.shape.size.x * door.scale.x / 2.0
	var player_half_width: float = player.get_node("Shape").shape.size.x / 2.0
	var blocked_left: float = door.position.x - half_width - player_half_width
	var blocked_right: float = door.position.x + half_width + player_half_width
	var leaf: StaticBody2D = native.bodies[0]
	assert(not leaf.get_meta("source_enabled") and leaf.collision_layer == 0)
	assert(native.invisible.collision_layer == 1)
	var commands: Array[bool] = []
	var passages: Array[bool] = []
	var invalidations: Array = []
	door.state_changed.connect(func(value: bool): commands.append(value))
	door.passability_changed.connect(func(value: bool): passages.append(value))
	door.attachments_invalidated.connect(func(surfaces): invalidations.append(surfaces))
	key(KEY_D, true)
	await frames(150)
	key(KEY_D, false)
	assert(player.is_on_floor() and absf(player.position.x - blocked_left) < 1)
	# Return to the left lever and strike it through the player's physical query.
	key(KEY_A, true)
	for frame in 60:
		await frames(1)
		if player.position.x < 380:
			break
	key(KEY_A, false)
	key(KEY_D, true)
	await frames(1)
	key(KEY_D, false)
	key(KEY_J, true)
	await frames(1)
	key(KEY_J, false)
	assert(door.is_open() and not door.is_passable())
	assert(commands == [true] and invalidations.size() == 1)
	assert(native.invisible.collision_layer == 1 and leaf.collision_layer == 0)
	assert(door.audio.next_variant.has("door_gear_open"))
	var initial_leaf_position: Vector2 = leaf.position
	door.open()  # Repeated open commands must not restart the animation/release clock.
	assert(commands.size() == 1)
	for frame in 100:
		await frames(1)
		if door.is_passable():
			break
		assert(native.elapsed < native.release_at + 0.02)
		assert(native.invisible.collision_layer == 1)
	assert(door.is_passable() and passages == [true])
	assert(native.elapsed >= 0.9 and native.elapsed < 1.1)
	assert(leaf.position.distance_to(initial_leaf_position) > 20)
	assert(native.invisible.collision_layer == 0 and not native.hard)
	key(KEY_D, true)
	await frames(110)
	key(KEY_D, false)
	assert(player.position.x > 690 and player.is_on_floor())
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	key(KEY_J, true)
	await frames(1)
	key(KEY_J, false)
	assert(not door.is_open() and not door.is_passable())
	assert(commands == [true, false] and passages == [true, false])
	assert(door.audio.next_variant.has("door_gear_close"))
	door.close()
	assert(commands.size() == 2)
	key(KEY_A, true)
	await frames(70)
	key(KEY_A, false)
	assert(absf(player.position.x - blocked_right) < 1)
	assert(native.hard and native.invisible.collision_layer == 1)
	# Closing interrupts the pending release; no stale timer opens the wall later.
	door.open()
	await frames(12)
	door.close()
	await frames(90)
	assert(not door.is_passable() and native.invisible.collision_layer == 1)
	door.open()
	await frames(90)
	assert(door.is_passable() and leaf.collision_layer == 0)
	# An initially-open, rotated/scaled second instance has isolated state and
	# collision settings. Its bodies inherit the wrapper's full transform.
	var other := Door.instantiate()
	other.settings = other.settings.duplicate()
	other.settings.initial_open = true
	other.settings.collider_release_fraction = 0.5
	other.solid_layers = 8
	other.position = Vector2(1400, 300)
	other.rotation = PI / 2
	other.scale = Vector2(1.5, 1.5)
	root.add_child(other)
	await frames(2)
	assert(other.is_open() and other.is_passable() and not door.settings.initial_open)
	other.close()
	assert(other.mechanism.invisible.collision_layer == 8 and door.is_passable())
	var wall: StaticBody2D = other.mechanism.invisible
	assert(wall.global_position.distance_to(other.to_global(wall.position)) < 0.001)
	other.open()
	await frames(25)
	assert(not other.is_passable())
	await frames(20)
	assert(other.is_passable())
	var abandoned: WeakRef = weakref(other.mechanism)
	other.close()
	other.queue_free()
	workshop.queue_free()
	await frames(2)
	assert(abandoned.get_ref() == null)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	for index in [2, 0, 2]:
		gallery.select_exhibit(index)
		await frames(3)
		assert(is_instance_valid(gallery.exhibit))
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_DOOR_PROBE_PASS")
	quit()
