extends SceneTree
const Workshop = preload("../Examples/IceWorkshop.tscn")
const IceBox = preload("../Devices/IceBox/IceBox.tscn")
const Burst = preload("../Core/DeviceBurst.gd")
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
	var ice: Node = workshop.ice
	var near: Node2D = workshop.get_node("Targets/Near")
	var protected: Node2D = workshop.get_node("Targets/Protected")
	assert(ice.visual_instances.size() == 4 and ice.ambient_emitters.size() == 2)
	assert(ice.mechanism.loop_started and not ice.mechanism.consumed)
	assert(ice.audio.get_child(0).stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	ice.bind_observer(protected)
	await frames(10)
	assert(ice.mechanism.outline < 0.01)
	ice.bind_observer(workshop.player, Vector2(0, -16))
	var starting_position: Vector2 = near.position
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	assert(near.position.distance_to(starting_position) > 1)
	assert(ice.mechanism.outline > 0.9)
	assert(ice.ambient_emitters.all(func(e): return e.emitted > 0))
	var events: Array[String] = []
	ice.charge_started.connect(func(): events.append("charge"))
	ice.discharged.connect(func(_affected): events.append("discharge"))
	key(KEY_J, true)
	await frames(1)
	key(KEY_J, false)
	assert(ice.mechanism.consumed and not ice.mechanism.fired and events == ["charge"])
	await frames(20)
	assert(not ice.mechanism.fired)
	await frames(25)
	assert(ice.mechanism.fired and events == ["charge", "discharge"])
	assert(ice.mechanism.affected == [near] and near.freeze_count == 1)
	assert(near.freeze_remaining > 4 and near.freeze_remaining < 5)
	assert(protected.position.distance_to(ice.position) < ice.settings.radius_pixels)
	for name in ["Protected", "Immune", "Distant"]:
		assert(workshop.get_node("Targets/" + name).freeze_count == 0)
	assert(ice.ambient_emitters.all(func(e): return not e.visible and e.particles.is_empty()))
	assert(
		ice.audio.get_children().all(
			func(voice): return voice.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED
		)
	)
	var bursts: Array = ice.get_children().filter(func(node): return node.get_script() == Burst)
	assert(bursts.size() == 1 and bursts[0].emitters.size() == 6)
	assert(bursts[0].emitters.any(func(e): return e.emitted > 0))
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	var frozen_position: Vector2 = near.position
	assert(not near.freeze(10))
	var second := IceBox.instantiate()
	second.position = ice.position
	workshop.add_child(second)
	second.bind_observer(workshop.player)
	second.register_target(near, near.freeze)
	await frames(2)
	assert(second.mechanism.loop_started and not second.mechanism.consumed)
	second.receive_hit(64)
	await frames(45)
	assert(second.mechanism.fired and second.mechanism.affected.is_empty())
	assert(near.freeze_count == 1 and near.freeze_remaining < 4)
	second.queue_free()
	ice.receive_hit(64)
	await frames(60)
	assert(near.position == frozen_position and near.freeze_count == 1)
	assert(events == ["charge", "discharge"])
	await frames(300)
	assert(near.freeze_remaining == 0 and near.position.distance_to(frozen_position) > 1)
	assert(ice.get_children().all(func(node): return node.get_script() != Burst))
	# R replaces the whole consumed scene; its old loop/VFX/animation children
	# must be released, while the host actors and their state stay independent.
	var old: WeakRef = weakref(ice)
	key(KEY_R, true)
	await frames(2)
	key(KEY_R, false)
	assert(old.get_ref() == null and not workshop.ice.mechanism.consumed)
	assert(workshop.ice.mechanism.loop_started)
	# A rotated/scaled, observer-free device uses transformed physics queries.
	var fixture := IceBox.instantiate()
	fixture.position = Vector2(1600, -2000)
	fixture.rotation = PI / 2
	fixture.scale = Vector2(1.5, 1.5)
	root.add_child(fixture)
	await frames(2)
	assert(not fixture.mechanism.loop_started)
	var field: Node = fixture.mechanism
	var center: Vector2i = field.cell_at(field.global_position)
	assert(field.cell_at(field.cell_center(center)) == center)
	var barriers: Array[Node] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			var wall := StaticBody2D.new()
			wall.transform = Transform2D(
				fixture.transform.x, fixture.transform.y, field.cell_center(center + Vector2i(x, y))
			)
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2.ONE * field.cell_size
			shape.shape = rectangle
			wall.add_child(shape)
			root.add_child(wall)
			barriers.append(wall)
	await frames(2)
	var filled: Dictionary = field.flood()
	assert(filled.size() == 5 and filled.has(center + Vector2i.RIGHT))
	assert(not filled.has(center + Vector2i(2, 0)))
	for wall: Node in barriers:
		wall.queue_free()
	await frames(2)
	filled = field.flood()
	assert(filled.size() > 600)
	var includes_outer_boundary := false
	for cell: Vector2i in filled:
		if (
			field._source_distance(field.global_position, field.cell_center(cell))
			>= fixture.settings.radius_pixels
		):
			includes_outer_boundary = true
	assert(includes_outer_boundary)
	# Dead registrations are discarded; a spent machine keeps its collider as
	# an attachment target, but no second charge or observer is required.
	var disposable := Node2D.new()
	root.add_child(disposable)
	fixture.register_target(disposable, func(_seconds): return true)
	disposable.queue_free()
	await frames(2)
	fixture.receive_hit(4)
	await frames(45)
	assert(fixture.mechanism.fired and fixture.targets.is_empty())
	assert(fixture.mechanism.collision_layer == fixture.hit_layers)
	fixture.queue_free()
	workshop.queue_free()
	await frames(2)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	for index in [3, 0, 3]:
		gallery.select_exhibit(index)
		await frames(3)
		assert(is_instance_valid(gallery.exhibit))
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_ICE_PROBE_PASS")
	quit()
