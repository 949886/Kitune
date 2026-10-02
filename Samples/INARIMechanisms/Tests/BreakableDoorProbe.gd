extends SceneTree
const Workshop = preload("../Examples/BreakableDoorWorkshop.tscn")
const Wood = preload("../Devices/BreakableDoor/WoodDoor.tscn")
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
	var wood: Node = workshop.wood
	var heavy: Node = workshop.heavy
	assert(wood.visual_instances.size() == 21 and heavy.visual_instances.size() == 21)
	assert(wood.can_attach_projectile() and not heavy.can_attach_projectile())
	assert(not heavy.receive_hit(64))
	var notifications: Array[String] = []
	wood.broken.connect(func(): notifications.append("wood"))
	heavy.broken.connect(func(): notifications.append("heavy"))
	heavy.debris_cleared.connect(func(): notifications.append("cleared"))
	key(KEY_D, true)
	await frames(100)
	key(KEY_D, false)
	assert(workshop.player.position.x > 300 and workshop.player.position.x < 340)
	key(KEY_J, true)
	await frames(2)
	key(KEY_J, false)
	assert(wood.is_broken() and not heavy.is_broken() and notifications == ["wood"])
	assert(wood.audio.next_variant.has("door_break"))
	var no_colliders := 0
	for piece: Dictionary in wood.mechanism.pieces:
		assert(is_instance_valid(piece.rigid) and piece.rigid.collision_mask == 1)
		assert(piece.rigid.collision_layer == 0 and piece.rigid.scale == Vector2.ONE)
		assert(is_equal_approx(piece.velocity.length(), 400.0))
		for body: StaticBody2D in piece.bodies:
			assert(body.collision_layer == 0)
		if piece.bodies.is_empty():
			no_colliders += 1
			assert(piece.rigid.get_child_count() == 0)
	assert(no_colliders == 2)
	key(KEY_D, true)
	await frames(150)
	key(KEY_D, false)
	assert(workshop.player.position.x > 640 and workshop.player.position.x < 690)
	key(KEY_J, true)
	await frames(2)
	key(KEY_J, false)
	assert(not heavy.is_broken() and heavy.audio.next_variant.has("metal_door_hit"))
	await frames(15)
	key(KEY_K, true)
	await frames(2)
	key(KEY_K, false)
	assert(heavy.is_broken() and notifications == ["wood", "heavy"])
	assert(heavy.audio.next_variant.has("metal_door_break"))
	assert(not heavy.receive_hit(8))
	assert(wood.mechanism.pieces.any(func(piece): return piece.rigid.contact_seen))
	assert(wood.mechanism.pieces.any(func(piece): return absf(piece.rigid.rotation) > 0.02))
	key(KEY_D, true)
	await frames(30)
	key(KEY_D, false)
	assert(workshop.player.position.x > 720)
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	var observed: Array[WeakRef] = []
	for piece: Dictionary in heavy.mechanism.pieces:
		observed.append(weakref(piece.rigid))
	while heavy.mechanism.elapsed < 5.0:
		await frames(1)
	for visual: Node2D in heavy.visual_instances:
		assert(absf(visual.modulate.a - 0.5) < 0.02)
	while heavy.mechanism.is_processing():
		await frames(1)
	await frames(2)
	assert(observed.all(func(ref): return ref.get_ref() == null))
	assert(notifications == ["wood", "heavy", "cleared"])
	assert(heavy.visual_instances.all(func(visual): return visual.modulate.a == 0))
	# Restore a host-saved broken state without replaying destruction effects.
	var restored := Wood.instantiate()
	restored.settings = restored.settings.duplicate()
	restored.settings.initial_broken = true
	root.add_child(restored)
	assert(restored.is_broken() and restored.audio.next_variant.is_empty())
	assert(restored.visual_instances.all(func(visual): return not visual.visible))
	assert(not wood.settings.initial_broken)
	restored.queue_free()
	# Invincibility and enemy damage accumulation remain independent per instance.
	var resistant := Wood.instantiate()
	resistant.settings = resistant.settings.duplicate()
	resistant.settings.invincible = true
	root.add_child(resistant)
	assert(not resistant.receive_hit(8))
	resistant.receive_enemy_damage(1000)
	assert(not resistant.is_broken())
	resistant.queue_free()
	var damaged := Wood.instantiate()
	damaged.settings = damaged.settings.duplicate()
	damaged.settings.health = 2
	root.add_child(damaged)
	damaged.receive_enemy_damage(1)
	assert(not damaged.is_broken())
	damaged.receive_enemy_damage(1)
	assert(damaged.is_broken())
	await frames(2)
	damaged.queue_free()
	# Capture exact world-space geometry/velocity at birth, before physics moves
	# a fragment. This checks rotated/scaled placement without solver tolerance.
	var fixture := Wood.instantiate()
	fixture.position = Vector2(1600, -2000)
	fixture.rotation = PI / 2
	fixture.scale = Vector2(1.5, 1.5)
	root.add_child(fixture)
	var births: Array[Dictionary] = []
	fixture.child_entered_tree.connect(func(node): _capture_birth(node, births))
	fixture.receive_hit(4)
	await frames(2)
	assert(births.size() == 21)
	for index in fixture.mechanism.pieces.size():
		var piece: Dictionary = fixture.mechanism.pieces[index]
		var birth: Dictionary = births[index]
		var expected_velocity: Vector2 = fixture.global_transform.basis_xform(piece.velocity)
		assert(birth.velocity.distance_to(expected_velocity) < 0.01)
		if not piece.bodies.is_empty():
			var polygon: CollisionPolygon2D = piece.bodies[0].get_child(0)
			var expected_point: Vector2 = polygon.global_transform * polygon.polygon[0]
			assert(birth.point.distance_to(expected_point) < 0.01)
	var fragment: RigidBody2D = fixture.mechanism.pieces[0].rigid
	var before: Vector2 = fragment.global_position
	fixture.position.x += 500
	await frames(2)
	# process_frame resumes this coroutine before Node._process updates the
	# visual transforms; inspect the completed rendered frame instead.
	await RenderingServer.frame_post_draw
	assert(fragment.global_position.distance_to(before) < 30)
	var piece: Dictionary = fixture.mechanism.pieces[0]
	var expected: Transform2D = (
		fragment.global_transform * piece.inverse_body * piece.visual_frames[0]
	)
	assert(piece.visuals[0].global_position.distance_to(expected.origin) < 0.01)
	var fragment_ref: WeakRef = weakref(fragment)
	fixture.queue_free()
	key(KEY_R, true)
	await frames(2)
	key(KEY_R, false)
	assert(fragment_ref.get_ref() == null and not workshop.wood.is_broken())
	workshop.queue_free()
	await frames(2)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	for index in [4, 0, 4]:
		gallery.select_exhibit(index)
		await frames(3)
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_BREAKABLE_DOOR_PASS")
	quit()


func _capture_birth(node: Node, births: Array[Dictionary]) -> void:
	if node is RigidBody2D:
		var entry := {"velocity": node.linear_velocity}
		if node.get_child_count() > 0:
			var polygon: CollisionPolygon2D = node.get_child(0)
			entry.point = polygon.global_transform * polygon.polygon[0]
		births.append(entry)
