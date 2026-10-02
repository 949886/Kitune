extends Node2D
## Pair coordinator: doors, checkpoint saves, input and cameras belong to the
## host. No source object ID is used to find another device in a scene tree.
signal state_changed(state: String)
signal started
signal succeeded
signal failed
signal start_door_requested
signal reward_doors_requested
signal checkpoint_requested(actor: Node, world_position: Vector2)
signal intro_save_requested
signal destination_save_requested(record: Dictionary, save_now: bool)
signal preview_requested(ticket: int, stops: Array, damping: float, threshold: float)
signal preview_cancelled(ticket: int)
signal timer_changed(seconds: float, visible: bool)
const Clock = preload("../../Core/Native/Runtime/InariTimerClock.gd")
const Configuration = preload("TrialSettings.gd")
@export var settings: Configuration = preload("TrialSettings.tres")
@export var start_path: NodePath = ^"Start"
@export var finish_path: NodePath = ^"Finish"
## Zero stops countdown; any positive value admits ordinary delta unchanged.
@export_range(0, 5, 0.01, "or_greater") var clock_scale := 1.0
var starter: Node2D
var destination: Node2D
var clock := Clock.new()
var state := "ready"
var intro_seen := false
var destination_record: Dictionary = {}
var saved_checkpoint := false
var clock_running := false
var preview_ticket := 0
var actor_ref: WeakRef
var eligible: Callable
var route_override: Array = []
var remaining: float:
	get:
		return clock.remaining


func _ready() -> void:
	starter = get_node(start_path)
	destination = get_node(finish_path)
	assert(starter != destination)
	clock.reset(settings.duration_seconds)
	intro_seen = settings.intro_seen
	starter.display.update(remaining, true)
	destination.display.update(remaining, true)
	if settings.destination_saved:
		destination_record = {
			"IsTimeOver": settings.destination_time_over,
			"CollEnabled": settings.destination_enabled
		}
		destination.display.update(0.0, true)
		if not settings.destination_enabled or settings.destination_time_over:
			destination.disable()
		if settings.destination_time_over:
			destination.play("timer_idle")
	starter.use_request = _begin
	destination.use_request = _finish
	clock.tick.connect(_tick)
	clock.expired.connect(_expired)


func bind_actor(actor: Node2D, can_use: Callable = Callable()) -> void:
	# A preview belongs to the original recipient. Rebinding invalidates its
	# ticket and restores host input/camera before attaching a different actor.
	if actor_ref != null and actor_ref.get_ref() != actor:
		cancel()
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_use
	starter.bind_actor(actor, can_use)
	destination.bind_actor(actor, can_use)


func _actor() -> Node2D:
	return actor_ref.get_ref() if actor_ref != null else null


func _begin(actor: Node) -> bool:
	if state == "preview" or state == "running":
		return false
	starter.disable()
	checkpoint_requested.emit(actor, starter.global_position)
	if intro_seen:
		_start(true)
	else:
		intro_seen = true
		intro_save_requested.emit()
		_set_state("preview")
		preview_ticket += 1
		var stops: Array = route_override.duplicate(true)
		if stops.is_empty():
			for stop: Dictionary in starter.document.record.camera_stops:
				stops.append(
					{
						"position": starter.to_global(Vector2(stop.position[0], stop.position[1])),
						"wait": stop.wait,
						"distance": stop.distance
					}
				)
		preview_requested.emit(
			preview_ticket, stops, settings.preview_damping, settings.preview_threshold
		)
	return true


## Host calls only after returning the camera and restoring input. Old tickets
## cannot start a destroyed/rebound/cancelled attempt. No implicit skip timeout.
func complete_preview(ticket: int) -> bool:
	if state != "preview" or ticket != preview_ticket or not is_instance_valid(_actor()):
		return false
	_start(false)
	return true


func _start(skipped: bool) -> void:
	_set_state("running")
	clock_running = true
	start_door_requested.emit()
	starter.play("timer_run")
	# The source retry branch starts these once here and once again in
	# StartTimeAttack. Preserve the duplicate audio calls, not extra clocks.
	if skipped:
		starter.audio.play_event("timer_start", starter)
		destination.audio.play_event("timer_loop", destination)
	for terminal: Node in [starter, destination]:
		terminal.play("timer_run")
		terminal.audio.play_event("timer_loop", terminal)
	starter.audio.play_event("timer_start", starter)
	clock.reset(settings.duration_seconds)
	timer_changed.emit(remaining, true)
	started.emit()


func _finish(actor: Node) -> bool:
	# Source destination does not test that the starter was used: the level's
	# physical gates enforce the route. Hosts may impose eligibility explicitly.
	if state == "preview" or state == "failed" or state == "cancelled":
		return false
	_set_state("success")
	clock_running = false
	_stop_audio()
	reward_doors_requested.emit()
	destination.audio.play_event("timer_stop", actor)
	destination_record = {"IsTimeOver": false, "CollEnabled": false}
	destination_save_requested.emit(destination_record.duplicate(true), true)
	timer_changed.emit(remaining, false)
	succeeded.emit()
	return true


func notify_checkpoint_saved() -> void:
	saved_checkpoint = true


func notify_actor_died() -> void:
	if saved_checkpoint:
		_fail(true)
	elif state == "preview":
		cancel()


func _expired() -> void:
	clock_running = false
	_fail(false)


func _fail(save_now: bool) -> void:
	if state == "cancelled":
		return
	_cancel_preview()
	_set_state("failed")
	destination.disable()
	destination.play("timer_idle")
	_stop_audio()
	destination.audio.play_event("timer_end", _actor())
	destination_record = {"IsTimeOver": true, "CollEnabled": false}
	destination_save_requested.emit(destination_record.duplicate(true), save_now)
	# Destination.OnDeadAfterSavePoint invalidates/saves the endpoint but does
	# not StopTimerAnimation. Its existing countdown/ticks continue until zero;
	# the starter hides timer UI only then. Do not silently fix that source quirk.
	timer_changed.emit(remaining, clock_running)
	failed.emit()


func _tick() -> void:
	for terminal: Node in [starter, destination]:
		terminal.display.update(remaining, false)
		terminal.audio.play_event("timer_tick", terminal)


func _process(delta: float) -> void:
	if state == "preview" and not is_instance_valid(_actor()):
		cancel()
	if clock_running:
		clock.step(delta, clock_scale > 0.0)
		if clock_running:
			timer_changed.emit(remaining, true)


func _set_state(value: String) -> void:
	state = value
	state_changed.emit(state)


func _stop_audio() -> void:
	for terminal: Node in [starter, destination]:
		if is_instance_valid(terminal):
			terminal.audio.stop_events(terminal)


func _cancel_preview() -> void:
	if state == "preview":
		preview_cancelled.emit(preview_ticket)
		preview_ticket += 1


func cancel() -> void:
	if state == "cancelled":
		return
	_cancel_preview()
	clock_running = false
	_stop_audio()
	starter.disable()
	destination.disable()
	_set_state("cancelled")
	timer_changed.emit(remaining, false)


func _exit_tree() -> void:
	_cancel_preview()
