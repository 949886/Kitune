extends SceneTree
## Tests the original notification/save/request contract, then traverses actual
## rooms by walking to and attacking their levers through physics queries.
const Observer = preload("../Devices/SceneObserver/SceneObserver.tscn")
const Workshop = preload("../Examples/SceneObserverWorkshop.tscn")
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


func contract() -> void:
	var observer := Observer.instantiate()
	observer.settings = observer.settings.duplicate(true)
	root.add_child(observer)
	assert(not observer.on_event_notify() and not observer.main_menu_move_notify())
	var state := {"CurrentSceneName": "origin", "SpawnPoint": Vector3(7, -9, 3), "Other": {"value": 8}}
	var busy := {"value": true}
	var trace: Array[String] = []
	var requests: Array[Dictionary] = []
	observer.bind_context(state, func(): return busy.value, "host_menu")
	observer.stop_player_requested.connect(func(): trace.append("stop"))
	observer.save_requested.connect(func(snapshot):
		assert(state.CurrentSceneName == observer.settings.destination)
		trace.append("save")
		snapshot.Other.value = 99)
	observer.back_to_main_menu.connect(func(): trace.append("menu"))
	observer.persistence_rebuild_requested.connect(func(): trace.append("persistence"))
	observer.transition_requested.connect(func(request):
		trace.append("transition")
		requests.append(request)
		busy.value = true)
	assert(not observer.notify(null, 0x7fffffff) and trace.is_empty())
	busy.value = false
	# Mask zero still invokes the override once; the shared dictionary changes
	# before save and retains unrelated nested records despite listener mutation.
	assert(observer.notify(null, 0))
	assert(trace == ["stop", "save", "persistence", "transition"])
	assert(state.BeforeSceneName == "origin" and state.BeforeSpawnPoint == Vector3(7, -9, 3))
	assert(state.SpawnPoint == Vector3.ZERO and state.Other.value == 8)
	assert(requests[0] == {"destination": "level22", "is_load": false, "skip_transition": false, "main_menu": false})
	assert(not observer.on_event_notify() and requests.size() == 1)
	trace.clear()
	busy.value = false
	observer.settings.stop_player = false
	observer.settings.destination = "second"
	observer.process_mode = Node.PROCESS_MODE_DISABLED
	assert(observer.notify(null, 123))
	assert(trace == ["save", "persistence", "transition"])
	assert(state.BeforeSceneName == "level22" and state.CurrentSceneName == "second")
	# Main-menu entry ignores busy and serialized destination; it does not save
	# or rewrite the gameplay record. Repeated events are not silently coalesced.
	trace.clear()
	var saved := state.duplicate(true)
	assert(observer.main_menu_move_notify() and observer.main_menu_move_notify())
	assert(trace == ["menu", "persistence", "transition", "menu", "persistence", "transition"])
	assert(state == saved and requests[-1].destination == "host_menu" and requests[-1].main_menu)
	observer.unbind_context()
	trace.clear()
	assert(not observer.notify() and not observer.main_menu_move_notify() and trace.is_empty())
	observer.queue_free()
	# Every exported original preset can be loaded under a renamed nested path.
	var base: String = get_script().resource_path.get_base_dir() + "/.."
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/Assets/SceneObserver/device.json"))
	assert(evidence.records.size() == 7)
	for id: String in evidence.records:
		var preset: Resource = load(base + "/Devices/SceneObserver/Presets/" + id + ".tres")
		assert(preset.destination == evidence.records[id].destination)
		assert(preset.stop_player == bool(evidence.records[id].source.fields.isPlayerStopped))
	print("SCENE_OBSERVER_CONTRACT_PASS")


func operate_lever(workshop: Node) -> void:
	key(KEY_D, true)
	for frame in 160:
		await frames(1)
		if workshop.player.position.x >= 445:
			break
	key(KEY_D, false)
	await frames(2)
	assert(workshop.player.position.x >= 440 and workshop.player.is_on_floor())
	key(KEY_J, true)
	await frames(2)
	key(KEY_J, false)
	assert(workshop.transition.is_loading())


func run() -> void:
	create_timer(50, true, false, true).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	contract()
	var workshop := Workshop.instantiate()
	root.add_child(workshop)
	await frames(8)
	await operate_lever(workshop)
	assert(workshop.saves.size() == 1 and workshop.player.controls_locked)
	assert(workshop.order == ["stop", "save", "persistence", "transition"])
	assert(workshop.saves[0].BeforeSceneName == "level16")
	assert(workshop.saves[0].BeforeSpawnPoint == Vector3(2, 3, 4))
	assert(workshop.saves[0].CurrentSceneName == "level22" and workshop.saves[0].SpawnPoint == Vector3.ZERO)
	assert(workshop.persistence == [workshop.player])
	var old: WeakRef = weakref(workshop.room)
	assert(not workshop.room.observer.on_event_notify())
	await frames(260)
	assert(workshop.swaps == 1 and old.get_ref() == null and not workshop.completed)
	assert(not workshop.player.controls_locked and workshop.room.return_to_menu)
	if not OS.get_environment("INARI_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("INARI_CAPTURE"))
	var state: Dictionary = workshop.out_game_data.duplicate(true)
	await operate_lever(workshop)
	await frames(260)
	assert(workshop.swaps == 2 and workshop.completed and workshop.menu_events == 1)
	assert(workshop.out_game_data == state and workshop.saves.size() == 1)
	assert(workshop.order == ["stop", "save", "persistence", "transition", "menu", "persistence", "transition"])
	key(KEY_R, true)
	await frames(2)
	key(KEY_R, false)
	assert(workshop.swaps == 0 and workshop.saves.is_empty() and not workshop.completed)
	assert(workshop.out_game_data == workshop.initial_data and not workshop.room.return_to_menu)
	# Removing the host while its fade is active releases rooms and coordinator.
	workshop.room.observer.on_event_notify()
	old = weakref(workshop.room)
	workshop.queue_free()
	await frames(3)
	assert(old.get_ref() == null)
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(15)
	await frames(3)
	var exhibit: WeakRef = weakref(gallery.exhibit)
	key(KEY_R, true)
	await frames(2)
	key(KEY_R, false)
	assert(gallery.exhibit == exhibit.get_ref() and gallery.exhibit.out_game_data.CurrentSceneName == "level16")
	gallery.select_exhibit(0)
	await frames(3)
	assert(exhibit.get_ref() == null)
	gallery.queue_free()
	await frames(3)
	print("PORTABLE_SCENE_OBSERVER_PASS")
	quit(0)
