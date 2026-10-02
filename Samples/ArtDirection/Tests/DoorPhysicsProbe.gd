extends SceneTree
## Real source fragments: launch, collision torque, fade and physics-body release.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
	var door: Node
	for node: Node in lab.stage.get_children():
		if node.has_method("receive_enemy_damage") and int(node.data.go) == 3459:
			door = node
	assert(door != null and door.pieces.size() == 21)
	assert(door.physics.launch_speed == 50.0)
	for excluded in ["Player", "Enemy", "Door"]:
		assert(excluded not in door.physics.collision_layers)
	for included in ["Ground", "Wall", "HardWall", "Platform", "InteractiveWall"]:
		assert(included in door.physics.collision_layers)
	await frames(12)
	seed(3459)
	door.interact(4, 1.0)
	await frames(2)
	var observed: Array[WeakRef] = []
	var free_flight := 0
	var without_colliders := 0
	for piece: Dictionary in door.pieces:
		var rigid: RigidBody2D = piece.rigid
		assert(rigid != null)
		observed.append(weakref(rigid))
		assert(is_equal_approx(piece.velocity.length(), 400.0) and piece.velocity.x >= 0.0)
		assert(rigid.mass == 2.0 and rigid.source_linear_drag == 0.5)
		assert(is_equal_approx(rigid.source_angular_drag, 0.05))
		assert(is_equal_approx(rigid.source_gravity.y, 9.8100004196167 * 16.0 * 3.0))
		assert(rigid.collision_mask == Collision.DOOR_DEBRIS_TARGET)
		assert((rigid.collision_layer & rigid.collision_mask) == 0)
		if piece.bodies.is_empty():
			without_colliders += 1
			assert(rigid.get_child_count() == 0)
		for shape: Node in rigid.get_children():
			assert(
				shape is CollisionPolygon2D and shape.build_mode == CollisionPolygon2D.BUILD_SOLIDS
			)
			assert(shape.polygon == piece.bodies[0].get_child(0).polygon)
		if not rigid.contact_seen:
			free_flight += 1
			assert(is_zero_approx(rigid.angular_velocity), "No initial random spin is authored")
	assert(free_flight > 0)
	assert(without_colliders == 2, "Retain the two disabled source fragment colliders")
	if DisplayServer.get_name() != "headless":
		lab.camera_rig.set_process(false)
		lab.camera.position = door.pieces[0].bodies[0].position + Vector2(120, 10)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
	await frames(180)
	var collided := 0
	var rotated := 0
	for piece: Dictionary in door.pieces:
		if piece.bodies.is_empty():
			assert(not piece.rigid.contact_seen)
			assert(piece.rigid.position.y > float(piece.body_transform[5]) + 100.0)
		if piece.rigid.contact_seen:
			collided += 1
		if absf(piece.rigid.rotation) > 0.02:
			rotated += 1
	assert(collided > 0, "Original debris polygons must contact the real factory floor")
	assert(rotated > 0, "Polygon contacts must be able to generate rotation")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_door_debris.png")
	await frames(120)
	for piece: Dictionary in door.pieces:
		assert(is_instance_valid(piece.rigid))
		for visual: Node2D in piece.visuals:
			assert(absf(visual.modulate.a - 0.5) < 0.025)
	await frames(310)
	assert(not door.is_processing())
	for body: WeakRef in observed:
		assert(body.get_ref() == null, "Faded debris must release its active physics body")
	for piece: Dictionary in door.pieces:
		for visual: Node2D in piece.visuals:
			assert(visual.modulate.a == 0.0)
	print("DOOR_PHYSICS_PASS contacts=", collided, " rotated=", rotated)
	lab.queue_free()
	await process_frame
	quit()
