extends SceneTree
## Real source BombMan: physics damage, separate prefab overrides, new renderer
## ownership, weak-point targeting, fade and live self-destruction after respawn.
var lab: Node


func _initialize() -> void:
	create_timer(70.0).timeout.connect(func(): quit(2))
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	var entries: Array = lab.profiles[2].practice_entries
	var selected := -1
	for index in entries.size():
		if entries[index].get("id") == "repeating_bomb":
			selected = index
	assert(selected >= 0)
	lab.load_level(2, selected)
	var room: Node = lab.stage.machinery.repeating
	var initial: Node = room.actors.enemy_1
	initial.set_physics_process(false)
	assert(initial.data.scout and initial.data.scout_distance == 6)
	assert(initial.get_meta("is_repeated") and not initial.get_meta("is_loaded"))
	assert(lab.stage.enemies.size() == 1 and initial.visuals.size() == 15)
	await frames(20)
	for attempt in 12:
		if initial.dead:
			break
		lab.player.position = initial.position + Vector2(-50,
			float(initial.data.bounds_offset[1]) + float(initial.data.bounds_size[1]) / 2.0)
		lab.player.velocity = Vector2.ZERO
		lab.player.facing = 1
		await frames(20)
		Input.action_press(lab.player.input_action("heavy_attack"))
		await frames(1)
		Input.action_release(lab.player.input_action("heavy_attack"))
		await frames(55)
	assert(initial.dead, "Actual native heavy-attack hitboxes must kill the authored actor")
	assert(room.persistence_removals == 1 and lab.stage.enemies.is_empty())
	assert(room.device.waiting.size() == 1 and room.replacement_count == 0)
	var old_visual: Node2D = initial.visuals[initial.data.primary_visual]
	assert(not old_visual.visible)
	await frames(300)
	assert(room.replacement_count == 0)
	for frame in 240:
		await frames(1)
		if room.replacement_count > 0:
			break
	assert(room.replacement_count == 1)
	var replacement: Node = room.actors.enemy_1
	assert(replacement != initial and not replacement.data.scout and replacement.data.scout_distance == 5)
	assert(replacement.health == replacement.data.profile.f_maximumHealth)
	assert(replacement.visuals.size() == 15 and lab.stage.enemies == [replacement])
	assert(lab.player.targeting.enemies == [replacement])
	assert(replacement.ranged_combat.target == lab.player)
	assert(replacement.global_position.distance_to(Vector2(
		room.source.record.members[0].source.respawnPosition.x,
		-room.source.record.members[0].source.respawnPosition.y) * 16) < 5)
	var graphic: Node2D = replacement.visuals[replacement.data.primary_visual]
	assert(graphic != old_visual and graphic.material != old_visual.material)
	assert(graphic.modulate.a < 0.5 and not old_visual.visible)
	# Keep the native AI active. Before it can self-destruct, verify the end of
	# the alpha coroutine and that the relocated weak-point collider can detect
	# the actual player rather than the prefab's original editing coordinates.
	await frames(16)
	assert(graphic.modulate == Color.WHITE)
	replacement.kunai.weak_points = 1
	# Geometry fixture must include the stack lifetime; a zero timer correctly
	# clears the manually-injected stack on the next native update.
	replacement.kunai.reset_time = float(lab.player.combat.ShurikenStackDisappearTime)
	replacement.weakpoint_presentation.hit(1)
	lab.player.position = replacement.position
	await frames(4)
	assert(replacement.weakpoint_presentation.contact_in_range)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/native-repeating.png")
	# Native sensing/ready/confirm/explosion must generate the second death.
	for frame in 500:
		await frames(1)
		if replacement.dead:
			break
	assert(replacement.dead and room.persistence_removals == 2)
	assert(room.device.waiting.size() == 1)
	var previous: WeakRef = weakref(replacement)
	var previous_visual: WeakRef = weakref(graphic)
	lab.load_level(2, 0)
	await frames(4)
	assert(previous.get_ref() == null and previous_visual.get_ref() == null)
	assert(not is_instance_valid(lab.stage.machinery.repeating))
	lab.queue_free()
	await frames(3)
	print("NATIVE_REPEATING_ROOM_PASS")
	quit()
