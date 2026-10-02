extends SceneTree
const Workshop = preload("../Examples/TimeTrialWorkshop.tscn")
const Terminal = preload("../Devices/TimeTrial/TimerStart.tscn")
const Gallery = preload("../Examples/DeviceGallery.tscn")


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


func tap(code: Key) -> void:
	key(code, true)
	await frames(1)
	key(code, false)
	await frames(2)


func walk_to(workshop: Node, x: float) -> void:
	var code := KEY_D if x > workshop.player.position.x else KEY_A
	key(code, true)
	for frame in 500:
		await frames(1)
		if absf(workshop.player.position.x - x) < 4:
			break
	key(code, false)
	await frames(2)
	assert(
		absf(workshop.player.position.x - x) < 5,
		"Real actor must reach the endpoint through open gates"
	)


func run() -> void:
	create_timer(55).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(10)
	var trial: Node = workshop.trial
	assert(trial.remaining == 30 and trial.state == "ready")
	assert(trial.starter.visual_instances.size() == 16)
	assert(trial.starter.document.sprite_info.size() == 12)
	assert(trial.starter.display.digits.size() == 4)
	assert(not trial.starter.interact(workshop.player))
	assert(not workshop.gates[0].is_passable() and not workshop.gates[1].is_passable())
	var events: Array = []
	trial.starter.audio.event_played.connect(func(event): events.append(event))
	await walk_to(workshop, workshop.start_position.x)
	await frames(15)
	assert(trial.starter.mechanism.outlines[0].get_shader_parameter("base_outline_alpha") > 0.9)
	await tap(KEY_F)
	assert(trial.state == "preview" and not workshop.player.input_enabled)
	assert(trial.remaining == 30 and workshop.save_data.intro_seen)
	var ticket: int = trial.preview_ticket
	assert(not trial.complete_preview(ticket - 1))
	var before: Vector2 = workshop.camera.position
	await frames(20)
	assert(workshop.camera.position.distance_to(before) > 1)
	# Source preview uses ordinary delta even when the countdown clock is zero.
	trial.clock_scale = 0
	for frame in 900:
		await frames(1)
		if trial.state != "preview":
			break
	assert(trial.state == "running" and trial.remaining == 30)
	assert(workshop.player.input_enabled and workshop.preview.ticket == -1)
	assert(events.count("timer_camera") == 4 and events.count("timer_start") == 1)
	assert(not trial.complete_preview(ticket))
	assert(not trial.starter.interact(workshop.player))
	assert(workshop.gates[0].is_open() and not workshop.gates[1].is_open())
	trial._process(0.5)
	assert(trial.remaining == 30)
	trial.clock_scale = 0.25
	trial._process(0.5)
	assert(trial.remaining == 29.5, "Positive custom scale is a gate, not a speed multiplier")
	trial.clock_scale = 1
	await walk_to(workshop, workshop.finish_position.x)
	assert(workshop.reward_count == 0 and not workshop.gates[1].is_open())
	assert(events.count("timer_tick") > 0)
	await tap(KEY_F)
	assert(trial.state == "success" and workshop.gates[1].is_open())
	assert(not trial.destination.is_available())
	assert(workshop.save_data.destination == {"IsTimeOver": false, "CollEnabled": false})
	var stopped: float = trial.remaining
	await frames(40)
	assert(trial.remaining == stopped)
	await walk_to(workshop, workshop.reward_position.x)
	await frames(180)
	assert(workshop.reward_count == 1 and workshop.money == 7)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://timer-workshop.png")
	var old: WeakRef = weakref(trial)
	await tap(KEY_R)
	assert(old.get_ref() == null)
	trial = workshop.trial
	assert(trial.settings.intro_seen and not trial.destination.is_available())
	assert(workshop.reward.is_collected() and workshop.reward_count == 1)
	assert(is_equal_approx(trial.destination.display.digits[2].value, 5.0 / 6))
	# Retry without a destination save: skip camera, preserve duplicate source
	# retry audio and actually time out without synthesizing an endpoint event.
	workshop.save_data.erase("destination")
	await tap(KEY_R)
	trial = workshop.trial
	events.clear()
	trial.starter.audio.event_played.connect(func(event): events.append(event))
	await walk_to(workshop, workshop.start_position.x)
	await tap(KEY_F)
	assert(trial.state == "running" and events.count("timer_start") == 2)
	trial._process(31)
	assert(trial.state == "failed" and not trial.destination.is_available())
	assert(not workshop.gates[1].is_open() and not workshop.save_data.has("destination"))
	await tap(KEY_R)
	await walk_to(workshop, workshop.start_position.x)
	await tap(KEY_F)
	trial = workshop.trial
	var end_events: Array = []
	trial.destination.audio.event_played.connect(func(event): end_events.append(event))
	trial.notify_checkpoint_saved()
	trial.notify_actor_died()
	assert(trial.state == "failed" and trial.clock_running)
	assert(workshop.save_data.destination.IsTimeOver)
	var death_remaining: float = trial.remaining
	trial._process(0.5)
	assert(is_equal_approx(trial.remaining, death_remaining - 0.5))
	trial._process(31)
	assert(not trial.clock_running and end_events.count("timer_end") == 2)
	await tap(KEY_R)
	await tap(KEY_H)
	assert(workshop.trial.state == "failed" and workshop.save_data.destination.IsTimeOver)
	await tap(KEY_R)
	assert(not workshop.trial.destination.is_available())
	assert(workshop.trial.destination_record.IsTimeOver)
	# Cancelling during preview must restore input and reject its stale callback.
	await tap(KEY_N)
	await walk_to(workshop, workshop.start_position.x)
	await tap(KEY_F)
	trial = workshop.trial
	ticket = trial.preview_ticket
	trial.cancel()
	assert(workshop.player.input_enabled and workshop.preview.ticket == -1)
	assert(not trial.complete_preview(ticket))
	await tap(KEY_R)
	# Independent terminal: real Area2D contact, custom layers, eligibility,
	# rotated/scaled transform and explicit binding, with no coordinator.
	var terminal := Terminal.instantiate()
	terminal.position = Vector2(3000, 3000)
	terminal.rotation = PI / 2
	terminal.scale = Vector2.ONE * 0.5
	terminal.actor_layers = 32
	root.add_child(terminal)
	var actor := CharacterBody2D.new()
	actor.collision_layer = 32
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 16)
	shape.shape = rectangle
	actor.add_child(shape)
	root.add_child(actor)
	actor.position = terminal.position
	await frames(4)
	assert(not terminal.interact(actor))
	terminal.bind_actor(actor, func(): return false)
	assert(not terminal.interact(actor))
	terminal.bind_actor(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	assert(not terminal.interact(actor))
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 4
	await frames(3)
	assert(not terminal.interact(actor))
	actor.collision_layer = 32
	await frames(3)
	assert(terminal.interact(actor) and not terminal.interact(actor))
	actor.queue_free()
	terminal.queue_free()
	workshop.queue_free()
	await frames(3)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(10)
	await frames(5)
	var released: WeakRef = weakref(gallery.exhibit.trial)
	gallery.select_exhibit(0)
	await frames(3)
	assert(released.get_ref() == null)
	gallery.queue_free()
	await frames(2)
	print("PORTABLE_TIME_TRIAL_PASS")
	quit()
