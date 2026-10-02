extends SceneTree
## Exercise actual kunai raycasts/teleport and live enemy stun/recovery in the
## imported room. Artificial blockers below isolate flood-fill corner cases.
var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2, 4)
	await frames(10)
	var ice: Node = lab.stage.machinery.ice_boxes.filter(func(box): return int(box.source.go) == 3526)[0]
	assert(lab.stage.machinery.ice_boxes.size() == 3)
	assert(ice.loop_started and not ice.consumed)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	var start_health: float = lab.player.damage.health
	lab.player.throw_projectile((ice.position - lab.player.body_shape.global_position).normalized())
	await frames(12)
	assert(lab.player.projectile_stuck and lab.player.projectile_surface.get_ref() == ice)
	assert(not ice.consumed, "Anchoring alone must not trigger ObjectShurikenComponent damage")
	assert(lab.player.try_teleport())
	assert(ice.consumed and not ice.fired)
	await frames(20)
	assert(not ice.fired)
	await frames(20)
	assert(ice.fired and ice.affected.size() > 0)
	assert(lab.player.damage.health == start_health)
	var enemy: Node = ice.affected[0]
	assert(enemy.stun_remaining == 5.0 and enemy.ranged_combat.state == "hit")
	assert(not enemy.stun(10.0), "Repeated freezing must not refresh AddHitTime")
	var pose: Array = enemy.motion_animation.tracks.map(func(track): return track.time)
	enemy.set_physics_process(true)
	await frames(50)
	assert(enemy.stun_remaining > 4.0 and enemy.stun_remaining < 4.3)
	assert(pose == enemy.motion_animation.tracks.map(func(track): return track.time))
	if DisplayServer.get_name() != "headless":
		lab.completion.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/ice-frozen-verified.png")
	var start_x: float = enemy.position.x
	var movement := {
		"Curve": enemy.data.profile.AttackInfoList[0].AttackMovementInfo.Curve,
		"Power": 0.5,
		"Duration": 0.1
	}
	enemy.receive_study_hit({"Damage": 1.0, "AttackKnockBackInfo": movement}, 1.0)
	await frames(10)
	assert(enemy.stun_remaining > 0.0 and enemy.knockback.is_empty())
	assert(enemy.position.x != start_x, "Frozen enemies must still respond to knockback")
	var remaining: float = enemy.stun_remaining
	enemy.on_source_time_scale(0.0)
	await frames(10)
	assert(enemy.stun_remaining == remaining)
	enemy.on_source_time_scale(1.0)
	await frames(270)
	assert(enemy.stun_remaining == 0.0 and enemy.ranged_combat.state != "hit")
	var before: float = ice.charge_clock
	ice.receive_study_hit({"source_actor": lab.player}, 1.0)
	await frames(2)
	assert(ice.charge_clock == before)
	# Retry releases the old one-shot object and starts a fresh loop voice.
	var old: WeakRef = weakref(ice)
	lab.respawn_player()
	await frames(20)
	assert(old.get_ref() == null)
	ice = lab.stage.machinery.ice_boxes.filter(func(box): return int(box.source.go) == 3526)[0]
	assert(not ice.consumed)
	for actor: Node in lab.stage.enemies:
		actor.set_physics_process(false)
	lab.player.position = ice.position + Vector2(-50, 25)
	lab.player.velocity = Vector2.ZERO
	lab.player.facing = 1.0
	Input.action_press(lab.player.input_action("attack"))
	await frames(1)
	Input.action_release(lab.player.input_action("attack"))
	await frames(30)
	assert(ice.consumed, "A real sword hit must activate the object hurtbox")
	await _check_flood(ice)
	lab.queue_free()
	await frames(2)
	print("ICE_BOX_PROBE_PASS")
	quit()


func _check_flood(ice: Node) -> void:
	# A closed ring prevents propagation, but its blocking cells are visited.
	# Use real PhysicsServer shapes away from the authored map.
	ice.position = Vector2(-20000, -10000)
	var center: Vector2i = ice.cell_at(ice.position)
	var blockers: Array[Node] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			var body := StaticBody2D.new()
			body.collision_layer = ice.Collision.SOLID
			body.set_meta("source_layer", "HardWall")
			body.position = ice.cell_center(center + Vector2i(x, y))
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2.ONE * ice.cell_size
			shape.shape = box
			body.add_child(shape)
			lab.stage.add_child(body)
			blockers.append(body)
	await frames(2)
	var filled: Dictionary = ice.flood()
	assert(filled.size() == 5 and filled.has(center + Vector2i.RIGHT))
	assert(not filled.has(center + Vector2i(2, 0)))
	for body: Node in blockers:
		body.queue_free()
	await frames(2)
	filled = ice.flood()
	assert(filled.size() > 600)
	var boundary := false
	for cell: Vector2i in filled:
		boundary = (
			boundary
			or (
				ice.position.distance_to(ice.cell_center(cell))
				>= float(ice.source.fields.range) * ice.cell_size
			)
		)
	assert(boundary)
