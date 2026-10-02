extends SceneTree
## Uses real factory trigger volumes and actors. Covers first-entry idempotence,
## source-origin conversion, respawn facing, invulnerability expiry inside spikes,
## enemy contact and scene reload. Test movement bypasses traversal only.

var saves := 0


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	for frame in 4:
		await physics_frame
		await process_frame


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	lab.set_physics_process(false)
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	assert(lab.stage.source_checkpoints.size() == 2)
	assert(lab.stage.spike_hazards.size() == 1)
	var checkpoint: Node = lab.stage.source_checkpoints[0]
	checkpoint.saved.connect(func(_point): saves += 1)
	player.damage.health = 1
	player.stamina = 2.0
	player.action_state = ""
	player.global_position = (
		checkpoint.to_global(checkpoint.get_child(0).position) - player.body_shape.position
	)
	await settle()
	assert(checkpoint.activated and saves == 1)
	assert(player.damage.health == 1 and player.stamina == 2.0, "Save is not a healing pickup")
	var saved: Vector2 = player.checkpoint
	var offset: Dictionary = player.tuning.body_offset
	var origin := (
		saved
		+ Vector2(-offset.x * player.units, -player.body_size.y / 2.0 + offset.y * player.units)
	)
	assert(
		(
			origin.distance_to(
				Vector2(checkpoint.source.spawn_origin[0], checkpoint.source.spawn_origin[1])
			)
			< 0.002
		)
	)
	assert(player.checkpoint_source == checkpoint.source.id)
	player.facing = -1.0
	player.respawn()
	assert(player.position == saved and player.facing == 1.0)
	await settle()
	checkpoint.enter(player)
	assert(saves == 1)
	var second: Node = lab.stage.source_checkpoints[1]
	player.position = second.to_global(second.get_child(0).position) - player.body_shape.position
	await settle()
	assert(second.activated and player.checkpoint_source == second.source.id)
	assert(player.checkpoint != saved)
	saved = player.checkpoint
	checkpoint.enter(player)
	assert(player.checkpoint == saved, "Returning to an already consumed save must not replace it")
	# Artificial route assistance must not supersede the source save.
	var route: Dictionary = lab.profiles[0]
	for point: Array in route.checkpoints:
		player.position = Vector2(point[0], point[1])
		lab._check_route_progress(route)
		assert(player.checkpoint == saved)
	# Actual spike polygon interior, beyond its boundary; do not call its hit
	# callback directly. This also catches accidentally using BUILD_SEGMENTS.
	var spike: Node = lab.stage.spike_hazards[0]
	var polygon: CollisionPolygon2D = spike.get_child(0)
	var center := Vector2.ZERO
	for point: Vector2 in polygon.polygon:
		center += point
	center /= polygon.polygon.size()
	assert(Geometry2D.is_point_in_polygon(center, polygon.polygon))
	player.position = polygon.to_global(center) - player.body_shape.position
	player.action_state = ""
	player.damage.blinking = true
	await settle()
	assert(not player.dead, "Spike must respect invulnerability")
	player.damage.blinking = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await settle()
	assert(not player.dead, "Reference comparison must not damage the paused player")
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await settle()
	assert(player.dead and player.damage.health == 0, "Stay must retry after invulnerability ends")
	player.respawn()
	assert(player.position == saved and player.facing == 1.0)
	var enemy: Node = lab.stage.enemies[0]
	enemy.position = polygon.to_global(center)
	await settle()
	assert(enemy.dead, "Spike must hit actual enemy bodies")
	lab.load_level(0)
	await process_frame
	assert(not lab.stage.source_checkpoints[0].activated)
	assert(lab.player.checkpoint_source.is_empty())
	lab.load_level(1)
	await process_frame
	assert(lab.stage.source_checkpoints.is_empty() and lab.stage.spike_hazards.is_empty())
	print("CHECKPOINT_HAZARD_PROBE_PASS")
	lab.queue_free()
	await process_frame
	quit()
