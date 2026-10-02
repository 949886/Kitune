extends RefCounted
## TimeAttackTimerBase checks the next-second boundary before decrementing.
## Its custom clock is a gate, not a multiplier of Unity's ordinary delta.
signal tick
signal expired
var remaining := 0.0
var next_second := 0.0


func reset(seconds: float) -> void:
	remaining = seconds
	next_second = seconds - 1.0


func step(delta: float, clock_enabled: bool) -> void:
	if remaining <= next_second:
		tick.emit()
		next_second -= 1.0
	if clock_enabled:
		remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		expired.emit()
