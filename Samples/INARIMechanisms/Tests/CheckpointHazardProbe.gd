extends SceneTree
## Actual overlaps in a copied package: gameplay route, callback boundaries,
## source Stay/Enter asymmetry, transformed geometry and host-owned persistence.
const Workshop = preload("../Examples/CheckpointHazardWorkshop.tscn")
const Checkpoint = preload("../Devices/Checkpoint/Checkpoint.tscn")
const Spike = preload("../Devices/SpikeStrip/SpikeStrip.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")
const TiledVisual = preload("../Core/DeviceTiledSprite.gd")


class Actor:
	extends CharacterBody2D
	var eligible := true
	var amounts: Array[float] = []

	func can_receive() -> bool:
		return eligible

	func receive(amount: float) -> bool:
		amounts.append(amount)
		eligible = false
		return true


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


func actor_at(point: Vector2, layer: int) -> Actor:
	var actor := Actor.new()
	actor.position = point
	actor.collision_layer = layer
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4
	shape.shape = circle
	actor.add_child(shape)
	root.add_child(actor)
	return actor


func run() -> void:
	# An assertion in a nested coroutine otherwise leaves a SceneTree running.
	create_timer(40).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(8)
	var checkpoint: Node = workshop.checkpoint
	var spike: Node = workshop.hazard
	var player: Node = workshop.player
	assert(checkpoint.visual_instances.is_empty())
	assert(spike.visual_instances.size() == 24 and spike.ambient_emitters.size() == 8)
	var tiled_count := 0
	for visual: Node in spike.visual_instances:
		if visual.get_script() == TiledVisual:
			tiled_count += 1
			assert(visual.destination.size.x > 0 and not visual.quads.is_empty())
	assert(tiled_count == 20)
	key(KEY_D, true)
	await frames(45)
	key(KEY_D, false)
	assert(checkpoint.is_activated() and workshop.saves == 1)
	assert(player.health == 37 and player.checkpoint.id == "workshop-entry")
	var spawn: Vector2 = (
		checkpoint.to_global(checkpoint.settings.spawn_offset) - player.source_origin_offset
	)
	assert(player.checkpoint.position.is_equal_approx(spawn))
	assert(spike.ambient_emitters.all(func(emitter): return emitter.emitted > 0))
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	key(KEY_D, true)
	await frames(135)
	key(KEY_D, false)
	assert(player.dead and player.damage_count == 1)
	key(KEY_R, true)
	await frames(3)
	key(KEY_R, false)
	assert(
		not player.dead and player.health == 100 and player.facing == 1,
		str([player.dead, player.health, player.facing, player.position])
	)
	assert(absf(player.global_position.x - spawn.x) < 0.01)
	assert(player.global_position.y >= spawn.y and player.global_position.y <= 400.1)
	await frames(8)
	assert(workshop.saves == 1)
	# Invulnerable entry does not disable subsequent player Stay damage.
	player.invulnerable_seconds = 0.25
	player.position = Vector2(690, 400)
	await frames(6)
	assert(not player.dead and player.damage_count == 1)
	await frames(20)
	assert(player.dead and player.damage_count == 2)
	await frames(6)
	assert(player.damage_count == 2)
	key(KEY_E, true)
	await frames(1)
	key(KEY_E, false)
	await frames(65)
	var enemy: Node = workshop.enemy
	assert(enemy.dead and enemy.damage_count == 1 and workshop.feedback_count == 1)
	# Enemies only receive Enter, including feedback when damage is rejected.
	enemy.respawn(Vector2(950, 400))
	await frames(5)
	enemy.invulnerable_seconds = 10
	enemy.position = Vector2(690, 400)
	await frames(5)
	assert(not enemy.dead and workshop.feedback_count == 2)
	enemy.invulnerable_seconds = 0
	await frames(6)
	assert(not enemy.dead and enemy.damage_count == 1)
	enemy.position = Vector2(950, 400)
	await frames(5)
	enemy.position = Vector2(690, 400)
	await frames(5)
	assert(enemy.dead and enemy.damage_count == 2 and workshop.feedback_count == 3)
	workshop.queue_free()
	await frames(4)
	await transformed_devices()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(5)
	await frames(3)
	var old_hazard: WeakRef = weakref(gallery.exhibit.hazard)
	var old_emitter: WeakRef = weakref(gallery.exhibit.hazard.ambient_emitters[0])
	gallery.select_exhibit(0)
	await frames(3)
	assert(old_hazard.get_ref() == null and old_emitter.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_CHECKPOINT_HAZARD_PASS")
	quit()


func transformed_devices() -> void:
	var fixture := Checkpoint.instantiate()
	fixture.settings = fixture.settings.duplicate()
	fixture.settings.facing = -1
	fixture.checkpoint_id = "transformed"
	fixture.position = Vector2(1600, -1200)
	fixture.rotation = PI / 2
	fixture.scale = Vector2.ONE * 1.5
	fixture.actor_layers = 32
	root.add_child(fixture)
	var inside: Vector2 = fixture.to_global(fixture.settings.trigger_offset)
	var outsider := actor_at(inside, 32)
	var actor := actor_at(inside + Vector2(600, 0), 32)
	var notifications: Array = []
	fixture.saved.connect(func(body, payload): notifications.append([body, payload]))
	fixture.bind_actor(actor, actor.can_receive)
	await frames(5)
	assert(not fixture.is_activated())
	actor.eligible = false
	actor.position = inside
	await frames(5)
	assert(not fixture.is_activated())
	actor.eligible = true
	await frames(5)
	assert(not fixture.is_activated(), "Source save is Enter, not Stay")
	actor.position += Vector2(600, 0)
	await frames(5)
	actor.position = inside
	await frames(5)
	assert(fixture.is_activated() and notifications.size() == 1)
	assert(notifications[0][0] == actor)
	var payload: Dictionary = notifications[0][1]
	assert(payload.id == "transformed" and payload.facing == -1)
	assert(payload.position.is_equal_approx(fixture.to_global(fixture.settings.spawn_offset)))
	assert(payload.direction.is_equal_approx(Vector2.UP))
	assert(actor.amounts.is_empty())
	fixture.mechanism.enter(actor)
	assert(notifications.size() == 1)
	var restored := Checkpoint.instantiate()
	restored.settings = restored.settings.duplicate()
	restored.settings.initially_activated = true
	restored.actor_layers = 32
	restored.position = Vector2(2100, -1000)
	root.add_child(restored)
	restored.bind_actor(actor)
	restored.saved.connect(func(_actor, data): notifications.append(data))
	actor.position = restored.to_global(restored.settings.trigger_offset)
	await frames(5)
	assert(restored.is_activated() and notifications.size() == 1)
	var spike := Spike.instantiate()
	spike.settings = spike.settings.duplicate()
	spike.settings.damage = 11
	spike.actor_layers = 32
	spike.position = Vector2(2600, -1800)
	spike.rotation = PI / 2
	spike.scale = Vector2.ONE * 1.5
	root.add_child(spike)
	spike.register_player(actor, actor.receive, actor.can_receive)
	# The first source polygon is a 272 x 48 strip, bottom-centered locally.
	actor.position = spike.to_global(Vector2(0, 20))
	await frames(5)
	assert(actor.amounts.is_empty())
	outsider.position = spike.to_global(Vector2(0, -24))
	actor.position = outsider.position
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(5)
	assert(actor.amounts.is_empty() and outsider.amounts.is_empty())
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(5)
	assert(actor.amounts == [11.0] and outsider.amounts.is_empty())
	spike.unregister_target(actor)
	actor.eligible = true
	await frames(5)
	assert(actor.amounts == [11.0])
	# Wrong physics layer remains excluded even after explicit registration.
	actor.collision_layer = 64
	spike.register_player(actor, actor.receive, actor.can_receive)
	await frames(5)
	assert(actor.amounts == [11.0])
	actor.queue_free()
	await frames(5)
	assert(spike.targets.is_empty())
	outsider.queue_free()
	fixture.queue_free()
	restored.queue_free()
	spike.queue_free()
	await frames(3)
