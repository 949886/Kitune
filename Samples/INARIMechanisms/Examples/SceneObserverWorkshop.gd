extends "PortalWorkshop.gd"
## Shared room/fade host with synchronous, in-memory storage. No disk save or
## original cutscene is simulated. SceneObserver never depends on this example.
@export var initial_data := {"CurrentSceneName": "level16", "SpawnPoint": Vector3(2, 3, 4)}
@export var menu_key := "menu"
var out_game_data: Dictionary
var saves: Array[Dictionary] = []
var persistence: Array[Node] = []
var menu_events := 0
var order: Array[String] = []


func _ready() -> void:
	out_game_data = initial_data.duplicate(true)
	super._ready()


func _install(scene: PackedScene) -> void:
	super._install(scene)
	if room.observer == null:
		return
	room.observer.bind_context(out_game_data, transition.is_loading, menu_key)
	room.observer.stop_player_requested.connect(_stop_player)
	room.observer.save_requested.connect(_save)
	room.observer.back_to_main_menu.connect(func():
		menu_events += 1
		order.append("menu"))
	room.observer.persistence_rebuild_requested.connect(_rebuild_persistence)
	room.observer.transition_requested.connect(_command_requested)
	if room.return_to_menu:
		room.lever.activated.connect(room.observer.main_menu_move_notify)
	else:
		room.lever.activated.connect(room.observer.on_event_notify)


func _stop_player() -> void:
	order.append("stop")
	player.begin_transition(_player_policy())


func _save(snapshot: Dictionary) -> void:
	order.append("save")
	saves.append(snapshot.duplicate(true))


func _rebuild_persistence() -> void:
	order.append("persistence")
	persistence.clear()
	persistence.append(player)


func _command_requested(data: Dictionary) -> void:
	order.append("transition")
	_requested(player, data)


func _player_policy() -> Dictionary:
	return {"maintain_input": false, "preserve_last_input": false,
		"injected_input": Vector2.ZERO, "grant_invincibility": false, "reset_dash": false}


func _began(actor: Node2D, data: Dictionary, _ticket: int) -> void:
	# The demo host blocks controls during its fade; the device's optional
	# pre-save input-stop event is tested separately from loader input policy.
	actor.begin_transition(_player_policy())
	caption.text = "返回示例菜单" if data.main_menu else "保存完成，正在进入下一场景"


func _finished(data: Dictionary, ticket: int) -> void:
	super._finished(data, ticket)
	completed = room.observer == null


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		# Rebind a fresh shared state before the parent installs the new room.
		out_game_data = initial_data.duplicate(true)
		saves.clear()
		persistence.clear()
		menu_events = 0
		order.clear()
	super._unhandled_key_input(event)
