extends SceneTree
## Drives actual controller inputs towards each route marker; reports stuck paths.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var failed_routes: Array[String] = []
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	for index in lab.profiles.size():
		# Mechanism routes require timed attacks/riding and are exercised by
		# MachineryProbe, rather than this movement-only waypoint driver.
		if lab.profiles[index].get("route_driver", "movement") != "movement":
			continue
		lab.load_level(index)
		var actions: Dictionary = {}
		for name in ["left", "right", "jump", "dash"]:
			actions[name] = lab.player.input_action(name)
		if lab.profiles[index].kind == "original_2d":
			actions.up = lab.player.input_action("up")
			actions.attack = lab.player.input_action("attack")
			actions.heavy_attack = lab.player.input_action("heavy_attack")
			actions.throw = lab.player.input_action("throw")
			actions.teleport = lab.player.input_action("teleport")
		for frame in range(60):
			await physics_frame
		var last_jump := -100
		var teleport_hold_until := -1
		for frame in range(1800):
			if lab.completed:
				break
			var objective: Dictionary = lab.profiles[index].objectives[lab.objective_index]
			var target := Vector2(objective.position[0], objective.position[1])
			var direction: float = signf(target.x - lab.player.position.x)
			for name in actions:
				if name == "teleport" and frame < teleport_hold_until:
					continue
				Input.action_release(actions[name])
			if absf(target.x - lab.player.position.x) > 8:
				Input.action_press(actions.right if direction > 0 else actions.left)
			var needs_jump: bool = lab.player.is_on_wall() or target.y < lab.player.position.y - 18
			var wall_climbing: bool = actions.has("up") and lab.player.climbing
			var needs_kunai: bool = (
				actions.has("throw")
				and target.y < lab.player.position.y - 130
				and not wall_climbing
			)
			if needs_kunai:
				# Use the real mouse aim and throw input to reach the original upper deck.
				# Sending an input event also verifies SubViewport coordinate conversion.
				needs_jump = false
				Input.action_release(actions.left)
				Input.action_release(actions.right)
				var aim: Vector2 = target + Vector2(0, -70)
				if objective.has("kunai_anchor"):
					aim = Vector2(objective.kunai_anchor[0], objective.kunai_anchor[1])
				var motion := InputEventMouseMotion.new()
				motion.position = lab.viewport.get_canvas_transform() * aim
				lab.viewport.push_input(motion, true)
				if not lab.player.projectile_active and frame % 60 == 0:
					Input.action_press(actions.throw)
				if (
					lab.player.projectile_active
					and lab.player.projectile_stuck
					and not Input.is_action_pressed(actions.teleport)
					and (
						is_instance_valid(lab.player.projectile_target)
						or (
							lab.player.projectile.position.y
							< target.y - lab.player.body_size.y / 2.0 - 10
						)
					)
				):
					# Hold across physics ticks; a press/release in the same tick can
					# otherwise disappear before the actor observes just_pressed.
					teleport_hold_until = frame + 3
					Input.action_press(actions.teleport)

			if wall_climbing:
				needs_jump = (
					direction != lab.player.facing and target.y >= lab.player.position.y - 18
				)
				if not needs_jump:
					Input.action_press(actions.up)
			if (
				actions.has("attack")
				and lab.player.is_on_wall()
				and not wall_climbing
				and frame % 30 == 0
			):
				Input.action_press(
					actions.heavy_attack if lab.player.is_on_floor() else actions.attack
				)
			if needs_jump and frame - last_jump > 17:
				Input.action_press(actions.jump)
				last_jump = frame
			if (
				not lab.player.is_on_floor()
				and not actions.has("up")
				and absf(target.x - lab.player.position.x) > 90
				and frame % 35 == 0
			):
				Input.action_press(actions.dash)
			if actions.has("up") and target.y < lab.player.position.y - 18:
				Input.action_press(actions.up)
			await physics_frame
		for action in actions.values():
			Input.action_release(action)
		print(
			"ROUTE ",
			lab.profiles[index].id,
			" complete=",
			lab.completed,
			" objective=",
			lab.objective_index,
			" position=",
			lab.player.position
		)
		if not lab.completed:
			failed_routes.append(lab.profiles[index].id)
			for hit_index in lab.player.get_slide_collision_count():
				var hit = lab.player.get_slide_collision(hit_index)
				print("BLOCK ", hit.get_collider().name, " normal=", hit.get_normal())
			if actions.has("up"):
				print("CLIMB ", lab.player.climbing, " state=", lab.player.action_state)
	lab.queue_free()
	await process_frame
	print(
		(
			"ROUTE_PROBE_PASS"
			if failed_routes.is_empty()
			else "ROUTE_PROBE_FAILED " + str(failed_routes)
		)
	)
	quit(0 if failed_routes.is_empty() else 1)
