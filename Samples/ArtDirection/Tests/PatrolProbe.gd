extends SceneTree
## Exercise imported walkable cells and both active patrols over full return legs.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	var stage: Node = lab.stage
	var captured: Dictionary = {}
	assert(stage.navigation.ground.size() == 543)
	assert(stage.navigation.grid.is_equal_approx(Transform2D.IDENTITY))
	assert(stage.navigation.nearest(Vector2(-5914.274, 5199.0)) == Vector2i(-370, -325))
	var source_path: Array[Vector2i] = stage.navigation.path(
		Vector2i(-370, -325), Vector2i(-364, -325)
	)
	assert(source_path.size() == 7)
	for index in source_path.size():
		assert(source_path[index] == Vector2i(-370 + index, -325))
	var observed: Dictionary = {}
	for enemy: Node in stage.enemies:
		# This fixture measures uninterrupted patrol cycles. Automatic acquisition
		# and the handoff back to patrol are covered by the combat probes.
		enemy.ranged_combat.target = null
		observed[enemy] = {
			"origin": enemy.position,
			"min_x": enemy.position.x,
			"max_x": enemy.position.x,
			"wait_frames": 0,
			"wait_cycles": 0,
			"directions": {},
			"moving_frames": 0
		}
	var active := 0
	for frame in 900:
		await physics_frame
		for enemy: Node in stage.enemies:
			var sample: Dictionary = observed[enemy]
			sample.min_x = minf(sample.min_x, enemy.position.x)
			sample.max_x = maxf(sample.max_x, enemy.position.x)
			if not enemy.patrol.enabled:
				assert(absf(enemy.position.x - sample.origin.x) < 0.01, "Non-scout started walking")
				continue
			if enemy.patrol.waiting:
				sample.wait_frames += 1
				assert(enemy.motion == "Idle" and is_zero_approx(enemy.velocity.x))
			elif sample.wait_frames > 0:
				assert(
					absi(int(sample.wait_frames) - 180) <= 2,
					"Source patrol wait must last 3 seconds"
				)
				sample.wait_cycles += 1
				sample.wait_frames = 0
			if absf(enemy.velocity.x) > 0.0:
				sample.moving_frames += 1
				sample.directions[signf(enemy.velocity.x)] = true
				assert(enemy.motion == "MoveX")
				assert(
					is_equal_approx(
						absf(enemy.velocity.x), float(enemy.data.profile.f_PatrolSpeed) * 16.0
					)
				)
				var track: Dictionary = enemy.motion_animation.tracks[0]
				assert("Patrol" in track.clip.clip)
				var visual: Node2D = enemy.visuals[enemy.data.primary_visual]
				assert(signf(visual.global_transform.determinant()) == enemy.facing)
				if DisplayServer.get_name() != "headless" and enemy.data.kind == "EnemyBowMan":
					if not captured.has(enemy.facing) and float(track.time) > 0.1:
						captured[enemy.facing] = true
						await RenderingServer.frame_post_draw
						var direction := "right" if enemy.facing > 0.0 else "left"
						root.get_texture().get_image().save_png(
							"res://tmp/art-direction/patrol-" + direction + ".png"
						)
			if frame % 180 == 0:
				print(
					"PATROL ",
					enemy.data.kind,
					" position=",
					enemy.position,
					" left=",
					enemy.patrol.left,
					" right=",
					enemy.patrol.right,
					" wait=",
					enemy.patrol.waiting
				)
	for enemy: Node in stage.enemies:
		if not enemy.patrol.enabled:
			continue
		active += 1
		var sample: Dictionary = observed[enemy]
		assert(sample.wait_cycles >= 2 and sample.directions.size() == 2)
		assert(sample.moving_frames > 100 and sample.max_x - sample.min_x > 100.0)
		assert(enemy.is_on_floor(), "Patrol stepped off its native ledge")
	assert(active == 2)
	lab.queue_free()
	await process_frame
	print("PATROL_PROBE_PASS")
	quit()
