extends Node
## Source timer endpoints and their actual door references. Clearing the combat
## room opens its gate; confirming the destination before zero opens the reward.
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Terminal = preload("res://Samples/ArtDirection/Runtime/InariTrialTerminal.gd")
const Clock = preload("res://Samples/ArtDirection/Runtime/InariTimerClock.gd")
const Digits = preload("res://Samples/ArtDirection/Runtime/InariTimerDigits.gd")
const Reward = preload("res://Samples/ArtDirection/Runtime/InariTrialReward.gd")

var source: Dictionary
var stage: Node
var player: Node
var session: Dictionary
var rules: Dictionary
var terminals: Dictionary = {}
var rewards: Array[Node] = []
var starter: Node
var destination: Node
var state := "ready"
var clock := Clock.new()
var display := Digits.new()
var remaining: float:
	get:
		return clock.remaining
	set(value):
		clock.remaining = value
var next_second: float:
	get:
		return clock.next_second
	set(value):
		clock.next_second = value
var rig: Node
var camera_marker := Node2D.new()
var camera_saved: Dictionary = {}
var camera_index := -1
var camera_distance := 0.0
var camera_wait := -1.0
var digits: Array[Dictionary] = []
var saved_checkpoint := false


func configure(record: Dictionary, owner_stage: Node, actor: Node, settings: Dictionary) -> void:
	source = record
	rules = settings
	stage = owner_stage
	player = actor
	session = stage.scene_options.trial_session
	for item: Dictionary in source.timers:
		var terminal := Terminal.new()
		stage.add_child(terminal)
		terminal.configure(item, self)
		terminals[int(item.id)] = terminal
		if item.kind == "TimeAttackTrigger":
			starter = terminal
	assert(starter != null)
	destination = terminals[int(starter.source.fields.dest.m_PathID)]
	remaining = (
		float(starter.source.fields.setMinute) * 60.0 + float(starter.source.fields.setSecond)
	)
	next_second = remaining - 1.0
	clock.tick.connect(
		func():
			_update_digits(false)
			for terminal: Node in terminals.values():
				stage.audio.play_event("timer_tick", terminal)
	)
	clock.expired.connect(_fail)
	for terminal: Node in terminals.values():
		display.configure(terminal.source.digits, stage.visuals_by_go)
	digits = display.digits
	_update_digits(true)
	for item: Dictionary in source.rewards:
		var reward := Reward.new()
		stage.add_child(reward)
		reward.configure(item, self)
		rewards.append(reward)
	add_child(camera_marker)
	player.health_changed.connect(_health_changed)
	call_deferred("_bind_checkpoint")


func _bind_checkpoint() -> void:
	for checkpoint: Node in stage.source_checkpoints:
		if int(checkpoint.source.go) == int(destination.source.checkpoint_go):
			checkpoint.saved.connect(func(_record): saved_checkpoint = true)


func use(terminal: Node) -> bool:
	if state == "preview" or state == "failed" or state == "success":
		return false
	terminal.disable()
	if terminal == starter:
		player.checkpoint = starter.position - _origin_offset()
		player.checkpoint_source = str(starter.source.fields.id)
		if session.get("intro_seen", false):
			_start()
		else:
			session.intro_seen = true
			_begin_preview()
	else:
		state = "success"
		_stop_audio()
		for pointer: Dictionary in destination.source.fields.doors:
			stage.machinery.battle.doors[int(pointer.m_PathID)].notify()
		stage.audio.play_event("timer_stop", player)
	return true


func _start() -> void:
	state = "running"
	var id := int(starter.source.fields.startDoor.m_PathID)
	if id:
		stage.machinery.battle.doors[id].notify()
	for terminal: Node in terminals.values():
		terminal.play("timer_run")
		stage.audio.play_event("timer_loop", terminal)
	stage.audio.play_event("timer_start", starter)


func _process(delta: float) -> void:
	if state == "preview":
		_preview_step(delta)
	elif state == "running":
		clock.step(delta, stage.combat_clock.scale_value > 0.0)
	display.step(delta)


func _update_digits(immediate: bool) -> void:
	display.update(remaining, immediate)


func _fail() -> void:
	state = "failed"
	destination.disable()
	destination.play("timer_idle")
	_stop_audio()
	stage.audio.play_event("timer_end", player)


func _health_changed(current: int, _maximum: int) -> void:
	if current <= 0 and saved_checkpoint and state != "failed":
		_fail()


func _stop_audio() -> void:
	for terminal: Node in terminals.values():
		stage.audio.stop_events(terminal)


func status_text() -> String:
	match state:
		"preview":
			return "路线预览"
		"running":
			return "限时挑战  %02d:%02d" % [int(remaining / 60.0), int(fmod(remaining, 60.0))]
		"failed":
			return "时间已到 · 奖励门保持关闭 · R 重试"
		"success":
			if rewards.all(func(reward): return reward.collected):
				return "奖励已领取 · 光点 %d" % int(session.get("money", 0))
			return "挑战成功 · 进入右侧房间领取奖励"
	return "靠近计时器，按 F / Y 开始挑战"


func _origin_offset() -> Vector2:
	return Vector2(
		-float(player.tuning.body_offset.x) * player.units,
		-player.body_size.y / 2.0 + float(player.tuning.body_offset.y) * player.units
	)


func _begin_preview() -> void:
	assert(rig != null)
	state = "preview"
	player.velocity = Vector2.ZERO
	player.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	camera_saved = {
		"source": rig.source,
		"framing": rig.framing,
		"offset": rig.target_offset,
		"depth": rig.target_depth
	}
	rig.source = rig.source.duplicate(true)
	rig.framing = rig.source.framing
	rig.source.screen_position[1] = 0.5
	rig.framing.m_UnlimitedSoftZone = true
	rig.source.damping[0] = starter.source.fields.cameraMoveSpeed
	rig.source.damping[1] = starter.source.fields.cameraMoveSpeed
	rig.target = camera_marker
	rig.target_offset = Vector2.ZERO
	rig.freeze_remaining = 0.0
	_next_camera_stop()


func _next_camera_stop() -> void:
	camera_index += 1
	camera_wait = -1.0
	if camera_index < starter.source.camera_stops.size():
		camera_marker.position = Assets.vec(starter.source.camera_stops[camera_index].position)
		stage.audio.play_event("timer_camera", starter)
	else:
		rig.target = player
		rig.target_offset = camera_saved.offset
		rig.source.screen_position = camera_saved.source.screen_position
		rig.source.damping[0] = 1.0
		rig.source.damping[1] = 1.0
	camera_distance = maxf(
		0.001,
		(
			absf(player.position.x - rig.camera_2d.position.x)
			if camera_index >= starter.source.camera_stops.size()
			else rig.camera_2d.global_position.distance_to(camera_marker.global_position)
		)
	)


func _preview_step(delta: float) -> void:
	var returning: bool = camera_index >= starter.source.camera_stops.size()
	var distance: float = (
		absf(player.position.x - rig.camera_2d.position.x)
		if returning
		else camera_marker.position.distance_to(rig.camera_2d.position)
	)
	var threshold: float = float(starter.source.fields.threshold) * player.units
	if not returning:
		var stop: Dictionary = starter.source.camera_stops[camera_index]
		rig.target_depth = (
			float(camera_saved.depth)
			- float(stop.distance) * clampf(1.0 - distance / camera_distance, 0.0, 1.0)
		)
	else:
		var t := clampf(1.0 - distance / camera_distance, 0.0, 1.0)
		rig.target_depth = lerpf(rig.target_depth, float(camera_saved.depth), t)
	if distance > threshold:
		return
	if returning:
		rig.source = camera_saved.source
		rig.framing = camera_saved.framing
		rig.target_depth = float(camera_saved.depth)
		player.process_mode = Node.PROCESS_MODE_INHERIT
		_start()
		return
	if camera_wait < 0.0:
		camera_wait = float(starter.source.camera_stops[camera_index].wait)
	camera_wait -= delta
	if camera_wait <= 0.0:
		_next_camera_stop()
