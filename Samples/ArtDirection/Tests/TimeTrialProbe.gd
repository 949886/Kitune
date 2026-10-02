extends SceneTree
## Real endpoint input, preview, enemy hurtboxes, gates and reward contact.
## Clock stepping isolates the long timeout without inventing a success event.
var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func press(action: String, count: int) -> void:
	Input.action_press(lab.player.input_action(action))
	await frames(count)
	Input.action_release(lab.player.input_action(action))
	await frames(2)


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2, 5)
	await frames(30)
	var trial: Node = lab.stage.machinery.trial
	var battle: Node = lab.stage.machinery.battle
	assert(trial.state == "ready" and trial.remaining == 30.0)
	assert(lab.player.interaction_target == trial.starter)
	assert(
		is_equal_approx(trial.starter.outlines[0].get_shader_parameter("base_outline_alpha"), 1.0)
	)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/trial-start.png")
	await press("interact", 1)
	assert(trial.state == "preview")
	assert(lab.player.process_mode == Node.PROCESS_MODE_DISABLED)
	for frame in 1100:
		await frames(1)
		if trial.state == "running":
			break
	assert(trial.state == "running" and trial.remaining > 29.0)
	assert(trial.camera_index == trial.starter.source.camera_stops.size())
	assert(lab.player.process_mode == Node.PROCESS_MODE_INHERIT)
	assert(battle.doors[10468].is_open)
	assert(not trial.starter.interact(lab.player))
	# Freeze the global custom clock without changing Unity/global delta.
	var before: float = trial.remaining
	lab.stage.combat_clock.set_scale(0.0)
	trial._process(0.5)
	assert(trial.remaining == before)
	lab.stage.combat_clock.set_scale(1.0)
	trial._process(31.0)
	assert(trial.state == "failed" and not trial.destination.available)
	assert(not battle.doors[10469].is_open and not lab.player.dead)
	# R retries the room, and the already-viewed native intro is skipped.
	lab.respawn_player()
	await frames(30)
	trial = lab.stage.machinery.trial
	battle = lab.stage.machinery.battle
	assert(trial.state == "ready")
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	await press("interact", 1)
	assert(trial.state == "running")
	for enemy: Node in lab.stage.enemies:
		if not enemy.spawn_active:
			continue
		for attempt in 8:
			if enemy.dead:
				break
			lab.player.position = (
				enemy.position
				+ Vector2(
					-50, float(enemy.data.bounds_offset[1]) + float(enemy.data.bounds_size[1]) / 2.0
				)
			)
			lab.player.velocity = Vector2.ZERO
			lab.player.facing = 1.0
			await frames(20)
			await press("heavy_attack", 1)
			await frames(55)
		assert(enemy.dead)
	assert(
		trial.state == "running", "The shipped time limit must accommodate the real damage sequence"
	)
	await frames(60)
	assert(battle.spawners[10472].status == "complete" and battle.doors[10467].is_open)
	lab.player.position = trial.destination.position + Vector2(-20, 35)
	lab.player.velocity = Vector2.ZERO
	await frames(20)
	assert(lab.player.interaction_target == trial.destination)
	await press("interact", 1)
	assert(trial.state == "success" and battle.doors[10469].is_open)
	await frames(80)
	# Walk through the actual opened reward gate and trigger the pickup.
	lab.player.wind_buff.request(1)
	lab.player.wind_buff.elapsed = 2.0
	await press("right", 65)
	assert(trial.rewards[0].collected and int(trial.session.reward_count) == 1)
	assert(lab.completed)
	# Part_7's component becomes enabled at the final Destroy key, after
	# length / animationSpeed (~1.11 s), then needs >0.3 s before capture.
	# Wait for real homing contacts instead of assuming all fragments start at t=0.
	for frame in 180:
		await frames(1)
		if trial.rewards[0].charges.values().all(func(charge): return charge.received):
			break
	assert(int(trial.session.money) == trial.rewards[0].source.charges.size())
	assert(trial.rewards[0].charges.values().all(func(charge): return charge.received))
	assert(
		trial.rewards[0].lights.values().all(
			func(light): return not light.enabled and is_zero_approx(light.energy)
		)
	)
	if DisplayServer.get_name() != "headless":
		lab.completion.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/trial-reward.png")
	lab.load_level(2, 5)
	await frames(10)
	trial = lab.stage.machinery.trial
	assert(trial.rewards[0].collected and int(trial.session.reward_count) == 1)
	assert(trial.rewards[0].visual_nodes.all(func(visual): return not visual.visible))
	assert(trial.rewards[0].lights.values().all(func(light): return not light.enabled))
	# A separate short run keeps the complete source AI active. Walk from the
	# starter into combat; no actor relocation or enemy freeze is used here.
	await press("interact", 1)
	await press("right", 130)
	assert(lab.player.position.x > -2600.0)
	await frames(100)
	# Enter the native destination checkpoint, then use the player's real damage
	# path. Its death signal must invalidate the endpoint before room reload.
	lab.load_level(2, 5)
	await frames(10)
	trial = lab.stage.machinery.trial
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	lab.player.set_physics_process(false)
	for checkpoint: Node in lab.stage.source_checkpoints:
		if int(checkpoint.source.go) == int(trial.destination.source.checkpoint_go):
			lab.player.position = (
				checkpoint.to_global(checkpoint.get_child(0).position)
				- lab.player.body_shape.position
			)
	await frames(4)
	assert(trial.saved_checkpoint)
	assert(lab.player.receive_damage(1.0))
	assert(lab.player.dead and trial.state == "failed" and not trial.destination.available)
	lab.queue_free()
	await frames(2)
	print("TIME_TRIAL_PROBE_PASS")
	quit()
