extends SceneTree
## Real physics entry and actual PackedScene replacement, plus all source
## variants and stale/cancelled host transactions in a renamed blank project.
const Workshop = preload("../Examples/PortalWorkshop.tscn")
const Portal = preload("../Devices/ScenePortal/ScenePortal.tscn")
const Transition = preload("../Devices/ScenePortal/SceneTransition.tscn")
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


func run() -> void:
	create_timer(50, true, false, true).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	var actor: CharacterBody2D = workshop.player
	var transition: Node = workshop.transition
	assert(transition.settings.fade_seconds == 2.0)
	await frames(8)
	assert(actor.is_on_floor() and not transition.is_loading())
	key(KEY_D, true)
	for frame in 220:
		await frames(1)
		if transition.is_loading():
			break
	key(KEY_D, false)
	assert(transition.is_loading() and actor.invincible and actor.dash_resets == 1)
	assert(actor.maintained_direction == Vector2(1, -1))
	assert(not workshop.room.portal.is_active() and workshop.room.portal.is_pending())
	var start: float = actor.position.x
	var first: int = transition.ticket
	assert(transition.request(actor, {"destination": "duplicate"}) == 0)
	await frames(45)
	assert(actor.position.x > start + 100 and workshop.swaps == 0)
	assert(transition.cover.modulate.a > 0.3 and transition.cover.modulate.a < 1)
	for frame in 180:
		await frames(1)
		if workshop.swaps == 1:
			break
	assert(workshop.swaps == 1 and transition.phase == transition.Phase.FADING_IN)
	assert(not transition.is_loading() and actor.controls_locked and not actor.invincible)
	assert(actor.maintained_direction == Vector2.ZERO and actor.dash_resets == 1)
	await frames(3)
	assert(workshop.previous_room.get_ref() == null)
	var spawn_x: float = actor.position.x
	await frames(150)
	assert(not transition.is_transitioning() and not actor.controls_locked)
	assert(absf(actor.position.x - spawn_x) < 0.1 and actor.is_on_floor())
	assert(not transition.finish_load(first))
	if not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	key(KEY_D, true)
	for frame in 220:
		await frames(1)
		if transition.is_loading():
			break
	key(KEY_D, false)
	start = actor.position.x
	assert(transition.is_loading() and not actor.invincible and actor.dash_resets == 1)
	assert(workshop.room.portal.is_active() and workshop.room.portal.is_pending())
	await frames(40)
	assert(absf(actor.position.x - start) < 0.1)
	await frames(230)
	assert(workshop.completed and workshop.swaps == 2 and not actor.controls_locked)
	assert(workshop.previous_room.get_ref() == null)
	key(KEY_R, true)
	key(KEY_R, false)
	await frames(4)
	assert(not workshop.completed and workshop.swaps == 0 and workshop.room.portal.is_active())
	workshop.queue_free()
	await frames(3)
	await trigger_fixtures()
	await transition_fixtures()
	await gallery_cleanup()
	print("PORTABLE_SCENE_PORTAL_PASS")
	quit()


func trigger_fixtures() -> void:
	var base := (Portal as PackedScene).resource_path.get_base_dir()
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(base + "/../../Assets/ScenePortal/device.json")
	)
	assert(data.records.size() == 7)
	for level: String in data.records:
		var settings: Resource = load(base + "/Presets/" + level + ".tres")
		var source: Dictionary = data.records[level]
		assert(settings.once == bool(source.fields.once))
		assert(settings.maintain_input == bool(source.fields.maintainInputOnTransition))
		assert(settings.destination == source.destination)
		assert(settings.trigger_size == Vector2(source.trigger.size[0], source.trigger.size[1]))
	var actor := CharacterBody2D.new()
	actor.collision_layer = 32
	actor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(12, 20)
	shape.shape = box
	actor.add_child(shape)
	root.add_child(actor)
	var fixture := Portal.instantiate()
	fixture.position = Vector2(3000, 3000)
	fixture.rotation = PI / 2
	fixture.scale = Vector2.ONE * 1.5
	fixture.actor_layers = 32
	fixture.portal_id = "host-exit"
	fixture.settings = load(base + "/Presets/level12.tres").duplicate(true)
	fixture.settings.maintain_input = true
	fixture.settings.input_direction = Vector2.RIGHT
	var state := {"loading": true, "eligible": true}
	fixture.bind_actor(actor, func(): return state.eligible, func(): return state.loading)
	var requests: Array = []
	fixture.transition_requested.connect(func(_actor, payload): requests.append(payload))
	actor.position = fixture.to_global(fixture.settings.trigger_offset)
	root.add_child(fixture)
	await frames(4)
	assert(requests.is_empty() and fixture.is_active())
	state.loading = false
	await frames(4)
	assert(requests.is_empty(), "Ignored Enter during loading must not become Stay activation")
	await reenter(actor, fixture)
	assert(requests.size() == 1 and fixture.is_pending() and fixture.is_active())
	assert(
		requests[0].input_direction == Vector2.RIGHT,
		"Input direction is world-space, not area rotation"
	)
	assert(
		requests[0].id == "host-exit" and requests[0].grant_invincibility and requests[0].reset_dash
	)
	assert(requests[0].injected_input == Vector2(1, -1) and not requests[0].preserve_last_input)
	fixture.settings.destination = "changed-after-request"
	assert(requests[0].destination == "level27")
	await reenter(actor, fixture)
	assert(requests.size() == 1, "Pending transaction suppresses duplicate entries")
	fixture.finish_request()
	await frames(3)
	assert(requests.size() == 1)
	state.eligible = false
	await reenter(actor, fixture)
	assert(requests.size() == 1)
	state.eligible = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	await reenter(actor, fixture)
	assert(requests.size() == 1)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 4
	await reenter(actor, fixture)
	assert(requests.size() == 1)
	actor.collision_layer = 32
	await frames(4)
	# Changing a layer can itself create a fresh contact. Resolve that request,
	# then prove an ordinary exit and enter still works for the repeat variant.
	fixture.finish_request()
	var before := requests.size()
	await reenter(actor, fixture)
	assert(requests.size() == before + 1)
	fixture.finish_request()
	fixture.settings.input_direction = Vector2.ZERO
	await reenter(actor, fixture)
	assert(requests.back().preserve_last_input and requests.back().injected_input == Vector2.ZERO)
	var adapter := preload("../Examples/TransitionPlayer.gd").new()
	adapter.left = true
	adapter.begin_transition(requests.back())
	assert(adapter.maintained_direction == Vector2.LEFT)
	adapter.end_transition()
	assert(not adapter.controls_locked and not adapter.invincible)
	adapter.free()
	before = requests.size() - 1
	fixture.finish_request()
	fixture.unbind_actor()
	await reenter(actor, fixture)
	assert(requests.size() == before + 1)
	fixture.queue_free()
	await frames(3)
	var once := Portal.instantiate()
	once.settings = load(base + "/Presets/level14.tres").duplicate(true)
	once.settings.initially_active = false
	once.actor_layers = 32
	once.position = Vector2(3000, 3000)
	once.bind_actor(actor)
	var entries: Array = []
	once.transition_requested.connect(func(_actor, payload): entries.append(payload))
	root.add_child(once)
	actor.position = once.to_global(once.settings.trigger_offset)
	await frames(4)
	assert(entries.is_empty() and not once.is_active())
	once.set_active(true)
	await frames(4)
	assert(entries.size() == 1 and not once.is_active())
	once.finish_request()
	await reenter(actor, once)
	assert(entries.size() == 1)
	once.set_active(true)
	await frames(4)
	assert(entries.size() == 2)
	actor.queue_free()
	await frames(3)
	once.set_active(true)
	await frames(3)
	assert(entries.size() == 2)
	once.queue_free()
	await frames(3)


func reenter(actor: Node2D, portal: Node2D) -> void:
	actor.position = portal.global_position + Vector2(1000, 1000)
	await frames(3)
	actor.position = portal.to_global(portal.settings.trigger_offset)
	await frames(3)


func transition_fixtures() -> void:
	var actor := Node2D.new()
	root.add_child(actor)
	var transition := Transition.instantiate()
	transition.settings = transition.settings.duplicate(true)
	transition.settings.fade_seconds = 0.08
	root.add_child(transition)
	var source := {"destination": "host-room", "nested": {"value": 1}}
	var ticket: int = transition.request(actor, source)
	source.nested.value = 2
	assert(transition.payload.nested.value == 1)
	assert(not transition.finish_load(ticket + 1))
	paused = true
	Engine.time_scale = 0
	await create_timer(0.18, true, false, true).timeout
	assert(transition.phase == transition.Phase.COVERED and transition.cover.modulate.a == 1)
	assert(transition.is_loading() and transition.request(actor, source) == 0)
	assert(transition.finish_load(ticket) and not transition.is_loading())
	assert(not transition.finish_load(ticket))
	await create_timer(0.18, true, false, true).timeout
	assert(not transition.is_transitioning() and not transition.cover.visible)
	Engine.time_scale = 1
	paused = false
	var cancelled: Array = []
	transition.cancelled.connect(func(_data, id): cancelled.append(id))
	ticket = transition.request(actor, source)
	transition.cancel()
	assert(cancelled == [ticket] and not transition.finish_load(ticket))
	var next: int = transition.request(actor, source)
	assert(next > ticket and not transition.finish_load(ticket))
	await create_timer(0.18, true, false, true).timeout
	assert(transition.finish_load(next))
	var replacement: int = transition.request(actor, source)
	assert(replacement > next and cancelled == [ticket, next])
	assert(not transition.finish_load(next))
	transition.queue_free()
	await frames(3)
	assert(cancelled == [ticket, next, replacement])
	actor.queue_free()
	await frames(3)


func gallery_cleanup() -> void:
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(8)
	await frames(4)
	var host: Node = gallery.exhibit
	var old: WeakRef = weakref(host)
	var coordinator: WeakRef = weakref(host.transition)
	host.transition.request(
		host.player,
		{
			"destination": "level12",
			"maintain_input": false,
			"input_direction": Vector2.ZERO,
			"grant_invincibility": false,
			"reset_dash": false
		}
	)
	assert(host.player.controls_locked)
	gallery.select_exhibit(0)
	await frames(4)
	assert(old.get_ref() == null and coordinator.get_ref() == null)
	gallery.queue_free()
	await frames(3)
