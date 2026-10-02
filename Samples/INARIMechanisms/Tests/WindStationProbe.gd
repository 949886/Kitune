extends SceneTree
## Real movement/attacks first, followed by deterministic timing and lifecycle
## checks. This script runs unchanged after copying/renaming the whole package.
const Workshop = preload("../Examples/WindWorkshop.tscn")
const Station = preload("../Devices/WindStation/WindStation.tscn")
const Buff = preload("../Devices/WindStation/WindBuff.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")


class Actor:
	extends CharacterBody2D
	var spawning := true
	var eligible := true
	var requests := 0

	func receive_buff() -> void:
		requests += 1

	func is_spawning() -> bool:
		return spawning

	func can_receive() -> bool:
		return eligible


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	var player: Node = workshop.player
	var buff: Node = player.buff
	var first: Node = workshop.first
	var second: Node = workshop.second
	var sounds: Array[String] = []
	var renewals: Array[String] = []
	first.audio.event_played.connect(func(event): sounds.append(event))
	buff.audio.event_played.connect(func(event): renewals.append(event))
	await frames(5)
	assert(first.visual_instances.size() == 2 and first.document.sprite_info.size() == 65)
	assert(first.animator.visual.material != second.animator.visual.material)
	var idle_frame: String = (
		first.animator._sample(first.animator.state, first.animator.state_time).sprite
	)
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	await frames(2)
	assert(buff.level == 1 and buff.extra_speed > 50 and buff.extra_speed < 64)
	assert(player.position.x > 280 and player.stamina == 46 and player.health == 1)
	assert(workshop.activation_count == 1 and first.has_granted_stamina())
	assert(not second.has_granted_stamina() and not second.is_cooling())
	assert(sounds == ["wind_buff_trigger"] and first.is_cooling())
	assert(
		first.animator.visual.texture.resource_path.ends_with(
			first.animator._sample(first.animator.state, first.animator.state_time).sprite + ".png"
		)
	)
	assert(
		first.animator._sample(first.animator.state, first.animator.state_time).sprite != idle_frame
	)
	if (
		DisplayServer.get_name() != "headless"
		and not OS.get_environment("INARI_CAPTURE").is_empty()
	):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	key(KEY_D, true)
	for frame in 100:
		await frames(1)
		if player.position.x > 475:
			break
	key(KEY_D, false)
	await frames(2)
	assert(player.position.x > 475 and player.position.x < 495)
	key(KEY_J, true)
	await frames(4)
	key(KEY_J, false)
	assert(workshop.target.dead and buff.level == 2 and buff.state.previous_level == 1)
	assert(buff.extra_speed > 90 and renewals == ["wind_buff_renewal"])
	key(KEY_D, true)
	for frame in 100:
		await frames(1)
		if workshop.activation_count == 2:
			break
	key(KEY_D, false)
	await frames(2)
	assert(workshop.activation_count == 2 and player.stamina == 91)
	assert(buff.level == 2 and buff.state.elapsed < 0.2 and buff.state.duration == 12)
	# Healing is a separate host policy, evaluated on entry even during cooldown.
	assert(first.is_cooling())
	player.story_mode = true
	player.position = Vector2(280, 400)
	var before: float = buff.state.elapsed
	await frames(5)
	assert(player.health == player.maximum_health and player.stamina == 91)
	assert(buff.state.elapsed > before and sounds.size() == 1 and workshop.activation_count == 2)
	# Custom character time stops decay; it does not stop the station's clock.
	buff.motion_time_scale = 0
	await frames(2)
	var elapsed: float = buff.state.elapsed
	var extra: float = buff.extra_speed
	var station_clock: float = first.mechanism.clock
	await frames(180)
	assert(buff.state.elapsed == elapsed and buff.extra_speed == extra)
	assert(first.mechanism.clock > station_clock + 2.9 and not first.is_cooling())
	assert(sounds.size() == 1, "Staying inside must not auto-reactivate a cooled station")
	player.position = Vector2(100, 400)
	await frames(5)
	player.position = Vector2(280, 400)
	await frames(5)
	assert(sounds.size() == 2 and player.stamina == 91 and workshop.activation_count == 3)
	# Tree pause stops both ordinary clocks and Animator progression.
	station_clock = first.mechanism.clock
	var animation_clock: float = first.animator.state_time
	workshop.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(5)
	assert(first.mechanism.clock == station_clock and first.animator.state_time == animation_clock)
	workshop.process_mode = Node.PROCESS_MODE_INHERIT
	buff.motion_time_scale = 1
	first.queue_free()
	await frames(3)
	assert(
		buff.level == 2 and buff.state.elapsed > 0,
		"Removing a station must not erase the actor's buff"
	)
	workshop.queue_free()
	await frames(3)
	await clock_rules()
	await binding_lifecycle()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(6)
	await frames(3)
	var old: WeakRef = weakref(gallery.exhibit.first)
	var old_buff: WeakRef = weakref(gallery.exhibit.player.buff)
	gallery.select_exhibit(0)
	await frames(3)
	assert(old.get_ref() == null and old_buff.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_WIND_STATION_PASS")
	quit()


func clock_rules() -> void:
	var buff := Buff.instantiate()
	root.add_child(buff)
	buff.set_physics_process(false)
	buff.notify_player_kill()
	assert(buff.level == 0 and not buff.state.active)
	buff.request_from_station()
	assert(buff.level == 1 and buff.extra_speed == 0 and buff.state.pending)
	buff.state.advance(0.5)
	assert(buff.extra_speed == 64 and buff.ratio == 0 and buff.state.elapsed == 0.5)
	for tick in 6:
		buff.state.advance(0.5)
	assert(buff.ratio == 0.5 and buff.extra_speed == 32)
	buff.state.time_scale = 0.3
	buff.state.advance(1)
	assert(absf(buff.state.elapsed - 3.8) < 0.00001)
	buff.state.time_scale = 1
	buff.notify_player_kill()
	assert(buff.level == 2 and buff.state.previous_level == 1 and buff.state.duration == 12)
	buff.state.advance(1)
	assert(buff.extra_speed == 96)
	buff.notify_player_kill()
	assert(buff.level == 2 and buff.state.previous_level == 2 and buff.state.elapsed == 0)
	for tick in 24:
		buff.state.advance(0.5)
	assert(buff.state.active and buff.state.elapsed == 12 and buff.extra_speed > 0)
	buff.state.advance(0.5)
	assert(buff.level == 0 and not buff.state.active and buff.extra_speed == 0)
	assert(buff.state.previous_level == 2)
	buff.request_from_station()
	buff.reset()
	assert(buff.level == 0 and not buff.state.pending)
	buff.queue_free()
	await frames(3)


func binding_lifecycle() -> void:
	var station := Station.instantiate()
	station.position = Vector2(1900, -1500)
	station.rotation = PI / 2
	station.scale = Vector2.ONE * 1.5
	station.actor_layers = 32
	root.add_child(station)
	var actor := Actor.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	actor.position = station.position + Vector2(400, 0)
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5
	collider.shape = circle
	actor.add_child(collider)
	root.add_child(actor)
	station.bind_actor(actor, actor.receive_buff, actor.is_spawning, actor.can_receive)
	var events: Array[String] = []
	station.began.connect(func(): events.append("begin"))
	station.activated.connect(func(_actor): events.append("activate"))
	station.cancelled.connect(func(): events.append("cancel"))
	station.stamina_requested.connect(func(_actor, amount): events.append("stamina:" + str(amount)))
	actor.position = station.to_global(Vector2(0, 25))
	await frames(6)
	assert(station.mechanism.pending_player.get_ref() == actor and actor.requests == 0)
	assert(events == ["stamina:45.0", "begin"])
	assert(not station.is_cooling() and station.mechanism.cooldown_until == 0)
	# Leaving while spawning does not cancel the original deferred coroutine.
	actor.position += Vector2(500, 0)
	await frames(6)
	actor.spawning = false
	await frames(3)
	assert(actor.requests == 1 and events.back() == "activate" and station.is_cooling())
	assert(station.mechanism.cooldown_until - station.mechanism.clock > 4.9)
	station.queue_free()
	await frames(3)
	station = Station.instantiate()
	station.position = actor.position
	station.actor_layers = 32
	root.add_child(station)
	actor.spawning = true
	station.bind_actor(actor, actor.receive_buff, actor.is_spawning)
	await frames(5)
	assert(station.mechanism.pending_player != null)
	station.unbind_actor()
	assert(station.mechanism.pending_player == null and station.animator.state == 0)
	actor.spawning = false
	await frames(5)
	assert(actor.requests == 1)
	# An unbound body cannot consume a fresh station; disabled hosts are ignored.
	var fresh := Station.instantiate()
	fresh.position = actor.position
	fresh.actor_layers = 32
	fresh.settings = fresh.settings.duplicate()
	fresh.settings.cooldown_seconds = 0
	root.add_child(fresh)
	await frames(5)
	assert(not fresh.has_granted_stamina())
	fresh.bind_actor(actor, actor.receive_buff, actor.is_spawning)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	fresh.mechanism.enter(actor)
	assert(not fresh.has_granted_stamina())
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	fresh.mechanism.enter(actor)
	fresh.mechanism.advance(1)
	assert(fresh.is_cooling(), "Even zero cooldown waits until the source Animator leaves Ready")
	fresh.animator.advance(0.1)
	fresh.mechanism.advance(1)
	assert(fresh.is_cooling())
	fresh.animator.advance(0.3)
	fresh.mechanism.advance(0)
	assert(not fresh.is_cooling())
	# Freed pending actors release the deferred request and restore idle visuals.
	station.bind_actor(actor, actor.receive_buff, actor.is_spawning)
	actor.spawning = true
	station.mechanism.enter(actor)
	assert(station.mechanism.pending_player != null)
	actor.queue_free()
	await frames(4)
	assert(station.mechanism.pending_player == null and station.animator.state == 0)
	fresh.queue_free()
	station.queue_free()
	await frames(3)
