extends Node
## MoveSceneObserver + the immediate GameManager call sequence. No actor lookup,
## file writes, scene path loading or global persistence manager lives here.
## The host supplies the same shared out-game dictionary to all scene commands.
signal stop_player_requested
signal save_requested(snapshot: Dictionary)
signal back_to_main_menu
signal persistence_rebuild_requested
signal transition_requested(request: Dictionary)
const Configuration = preload("ObserverSettings.gd")
@export var settings: Configuration = preload("Presets/level16_690.tres")
var out_game_data: Dictionary
var loading: Callable
var main_menu_destination := ""
var bound := false


## Keep the original Vector3 spawn record opaque: a host may store Godot units,
## Unity units or another coordinate space. Only the next spawn is reset to zero.
## Save listeners must persist synchronously before transition_requested fires.
func bind_context(data: Dictionary, is_loading: Callable, main_menu := "") -> void:
	assert(data.has("CurrentSceneName") and data.has("SpawnPoint"))
	assert(data.SpawnPoint is Vector3)
	assert(is_loading.is_valid())
	out_game_data = data
	loading = is_loading
	main_menu_destination = main_menu
	bound = true


func unbind_context() -> void:
	bound = false
	out_game_data = {}
	loading = Callable()
	main_menu_destination = ""


## ObserverMask is zero in this source class. Its override nevertheless calls
## OnNotify once after base.Notify, regardless of subject/type or component
## process mode. Direct event calls also do not implement one-shot activation.
func notify(_subject: Object = null, _observer_type: int = 0) -> bool:
	return on_event_notify()


func on_event_notify() -> bool:
	if not bound or not loading.is_valid() or bool(loading.call()):
		return false
	assert(not settings.destination.is_empty(), "Bind a scene destination before notifying")
	if settings.stop_player:
		stop_player_requested.emit()
	# MoveScene2NextStage copies the current state before clearing the next spawn.
	# Capture the method argument before save listeners can mutate configuration.
	var destination := settings.destination
	out_game_data.BeforeSceneName = out_game_data.CurrentSceneName
	out_game_data.BeforeSpawnPoint = out_game_data.SpawnPoint
	out_game_data.CurrentSceneName = destination
	out_game_data.SpawnPoint = Vector3.ZERO
	save_requested.emit(out_game_data.duplicate(true))
	_request(destination, false)
	return true


## Source MainMenuMoveNotify is a different entry point: no loading guard,
## stop-input call or out-game save. Its target comes from the host's menu
## setting, NOT this observer's serialized destination (level28 differs).
func main_menu_move_notify() -> bool:
	if not bound or main_menu_destination.is_empty():
		return false
	back_to_main_menu.emit()
	_request(main_menu_destination, true)
	return true


func _request(destination: String, menu: bool) -> void:
	# Source MoveScene clears the persistence registry then adds the player;
	# this synchronous host hook must complete before its loading coroutine starts.
	persistence_rebuild_requested.emit()
	transition_requested.emit({"destination": destination, "is_load": false,
		"skip_transition": false, "main_menu": menu})
