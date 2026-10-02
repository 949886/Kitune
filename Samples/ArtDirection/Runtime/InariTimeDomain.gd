extends Node
## INARI TimeManager changes subscribers, never Unity's global time for hit-stop.

signal scale_changed(value: float)

var scale_value := 1.0
var remaining := 0.0
var subscribers: Array[WeakRef] = []


func _ready() -> void:
	process_physics_priority = -100


func subscribe(target: Node) -> void:
	for reference: WeakRef in subscribers:
		if reference.get_ref() == target:
			return
	subscribers.append(weakref(target))
	target.on_source_time_scale(scale_value)


func stop_frames(count: int, fixed_timestep: float) -> void:
	remaining = count * fixed_timestep
	set_scale(0.0)


func set_scale(value: float) -> void:
	if scale_value == value:
		return
	scale_value = maxf(value, 0.0)
	var alive: Array[WeakRef] = []
	for reference: WeakRef in subscribers:
		var target: Node = reference.get_ref()
		if is_instance_valid(target):
			target.on_source_time_scale(scale_value)
			alive.append(reference)
	subscribers = alive
	scale_changed.emit(scale_value)


func reset() -> void:
	remaining = 0.0
	set_scale(1.0)


func _physics_process(delta: float) -> void:
	if scale_value == 0.0:
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			set_scale(1.0)
