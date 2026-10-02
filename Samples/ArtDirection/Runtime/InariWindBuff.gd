extends RefCounted
## BuffComponent's sampled-before-increment decay, paused with the custom coroutine clock.

var actor: CharacterBody2D
var level := 0
var previous_level := 0
var base_speed := 0.0
var extra_speed := 0.0
var ratio := 0.0
var elapsed := 0.0
var duration := 0.0
var active := false
var pending := false
## Portable hosts supply profiles and their custom clock; native players retain
## the same field-based path. The profile's speed unit is chosen by the host.
var use_host_adapter := false
var speeds := PackedFloat32Array()
var durations := PackedFloat32Array()
var time_scale := 1.0
signal feedback_requested(current_level: int, old_level: int)


func request(next_level: int) -> void:
	previous_level = level
	level = next_level
	base_speed = 0.0
	extra_speed = 0.0
	ratio = 0.0
	elapsed = 0.0
	duration = (
		float(durations[level])
		if use_host_adapter
		else float(actor.combat.WindBuffDurations[level])
	)
	active = true
	pending = true


func advance(delta: float) -> void:
	if not active:
		return
	var speed_scale: float = time_scale if use_host_adapter else actor.source_time_scale
	if speed_scale <= 0.0:
		return
	# StartCoroutine registers work; the first custom-manager update initializes it.
	if pending:
		base_speed = (
			float(speeds[level]) if use_host_adapter else float(actor.combat.WindBuffSpeeds[level])
		)
		pending = false
	if elapsed >= duration:
		reset()
		return
	ratio = elapsed / duration
	extra_speed = lerpf(base_speed, 0.0, ratio)
	elapsed = PackedFloat32Array([elapsed + delta * speed_scale])[0]


func on_player_kill() -> void:
	if use_host_adapter:
		feedback_requested.emit(level, previous_level)
		if level > 0:
			request(mini(level + 1, mini(speeds.size(), durations.size()) - 1))
		return
	actor.stamina_feedback.trigger(level, previous_level)
	var maximum: int = (
		mini(actor.combat.WindBuffSpeeds.size(), actor.combat.WindBuffDurations.size()) - 1
	)
	var next_level := level if level >= maximum else level + 1
	# Native kills renew an existing buff, but cannot grant its first level.
	if level > 0 and next_level >= 0 and next_level < actor.combat.WindBuffDurations.size():
		request(next_level)


func reset() -> void:
	# ResetBuff clears current BuffInfo, retaining PreviousBuffInfo for the outline gate.
	level = 0
	base_speed = 0.0
	extra_speed = 0.0
	ratio = 0.0
	elapsed = 0.0
	duration = 0.0
	active = false
	pending = false
