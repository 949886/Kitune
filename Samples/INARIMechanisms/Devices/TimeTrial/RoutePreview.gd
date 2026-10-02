extends Node
## Optional 2D camera adapter for the source waypoint sequence. A host with its
## own camera rig can consume TimeTrial.preview_requested directly instead.
signal depth_changed(source_depth_offset: float)
var trial: Node
var camera: Camera2D
var actor_ref: WeakRef
var set_input_enabled: Callable
var stops: Array = []
var index := -1
var ticket := -1
var damping := 2.0
var threshold := 32.0
var initial_distance := 1.0
var wait_remaining := -1.0
var saved: Dictionary = {}
var depth := 0.0


func bind(coordinator: Node, view: Camera2D, actor: Node2D, input_control: Callable) -> void:
	assert(not is_instance_valid(trial), "Create one adapter per coordinator")
	trial = coordinator
	camera = view
	actor_ref = weakref(actor)
	set_input_enabled = input_control
	trial.preview_requested.connect(_begin)
	trial.preview_cancelled.connect(_cancel)


func _begin(id: int, points: Array, move_damping: float, distance_threshold: float) -> void:
	if not is_instance_valid(camera) or actor_ref.get_ref() == null:
		trial.cancel()
		return
	ticket = id
	stops = points
	damping = move_damping
	threshold = distance_threshold
	index = -1
	saved = {
		"offset": camera.offset,
		"smoothing": camera.position_smoothing_enabled,
		"position": camera.global_position,
		"process": camera.process_mode
	}
	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	# Host owns movement/input state. Do not disable its entire player node.
	if set_input_enabled.is_valid():
		set_input_enabled.call(false)
	_next()


func _next() -> void:
	index += 1
	wait_remaining = -1.0
	var actor: Node2D = actor_ref.get_ref()
	if index < stops.size():
		initial_distance = maxf(0.001, camera.global_position.distance_to(stops[index].position))
		trial.starter.audio.play_event("timer_camera", trial.starter)
	else:
		camera.offset = saved.offset
		initial_distance = maxf(0.001, absf(camera.global_position.x - actor.global_position.x))


func _process(delta: float) -> void:
	if ticket < 0:
		return
	var actor: Node2D = actor_ref.get_ref()
	if not is_instance_valid(actor) or not is_instance_valid(camera):
		trial.cancel()
		return
	var returning := index >= stops.size()
	var target: Vector2 = actor.global_position if returning else stops[index].position
	var distance := (
		absf(camera.global_position.x - target.x)
		if returning
		else camera.global_position.distance_to(target)
	)
	if wait_remaining >= 0.0:
		# Cinemachine keeps following the last target during the authored wait.
		camera.global_position += (
			(target - camera.global_position) * (1.0 - exp(log(0.01) * delta / damping))
		)
		# MyWaitForSeconds compares Unity Time.time, not GameManager's custom
		# TimeScale. Both its waits and camera movement use ordinary delta.
		wait_remaining -= delta
		if wait_remaining <= 0.0:
			_next()
		return
	if distance > threshold:
		var t := clampf(1.0 - distance / initial_distance, 0.0, 1.0)
		depth = lerpf(depth, 0.0, t) if returning else -float(stops[index].distance) * t
		depth_changed.emit(depth)
		# Cinemachine Damper leaves 1% residual after its damping interval.
		var duration := 1.0 if returning else damping
		camera.global_position += (
			(target - camera.global_position) * (1.0 - exp(log(0.01) * delta / duration))
		)
		return
	if returning:
		var completed := ticket
		_restore(false)
		trial.complete_preview(completed)
	else:
		wait_remaining = float(stops[index].wait)


func _cancel(id: int) -> void:
	if ticket == id:
		_restore(true)


func _restore(cancelled: bool) -> void:
	if ticket < 0:
		return
	ticket = -1
	if is_instance_valid(camera):
		camera.offset = saved.offset
		camera.position_smoothing_enabled = saved.smoothing
		if cancelled:
			camera.global_position = saved.position
	depth = 0.0
	depth_changed.emit(depth)
	if set_input_enabled.is_valid():
		set_input_enabled.call(true)


func _exit_tree() -> void:
	_restore(true)
