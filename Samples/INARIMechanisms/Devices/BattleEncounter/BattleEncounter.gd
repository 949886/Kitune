extends Node2D
## A reusable SpawnManager coordinator. The host owns enemy implementation,
## hurtboxes, arrival artwork, doors, timelines and persistent storage.
signal state_changed(state: String, phase: int, remaining: int)
signal member_registered(key: StringName, actor: Node2D)
signal arrival_requested(key: StringName, world_position: Vector2, kind: String)
signal wave_arrival_requested(members: Array)
signal completed
signal save_requested(record: Dictionary)
const Clock = preload("../../Core/Native/Runtime/InariEncounterClock.gd")
const Configuration = preload("EncounterSettings.gd")
@export var settings: Configuration = preload("EncounterSettings.tres")
## Restore before adding to tree. Completed saves suppress all enemies and
## do not replay completion/door events; restore doors independently.
@export var restored_end := false
@export_range(0, 5, 0.01, "or_greater") var custom_time_scale := 1.0
var clock := Clock.new()
var bindings: Dictionary = {}
var keys: Array[StringName] = []
var started := false
var _last_tick := 0
var _last_status := ""
var _last_phase := -1
var _last_remaining := -1


func _ready() -> void:
	var phases := []
	for wave: PackedStringArray in settings.waves:
		var members := []
		for key: String in wave:
			assert(not key in keys, "Each enemy must belong to one configured wave")
			keys.append(StringName(key))
			members.append({"m_PathID": keys.size()})
		phases.append({"EnemyPrefab": members})
	var selections := []
	for key: String in settings.thresholds:
		assert(StringName(key) in keys, "Threshold key must belong to a configured wave")
		selections.append({"enemyStateMachine": {"m_PathID": keys.find(StringName(key)) + 1},
			"hpRatio": float(settings.thresholds[key])})
	clock.configure({"spawnDatas": phases, "selectedEnemy": selections, "IsOnField": settings.on_field,
		"PhaseChangingTime": settings.phase_delay, "EndTime": settings.end_delay,
		"waitingTime": settings.peaceful_delay}, settings.arrival_delay, restored_end)
	clock.phase_registered.connect(_registered)
	clock.arrival_requested.connect(_arrival)
	clock.phase_visible.connect(_visible_phase)
	clock.phase_wild.connect(_wild_phase)
	clock.completed.connect(func(): completed.emit())
	_last_tick = Time.get_ticks_usec()
	# Deferred start permits a host parent's _ready to bind its actors. Missing
	# bindings leave a reviewable waiting encounter; they never count as kills.
	call_deferred("start")


## Callbacks are set_active(bool) and set_peaceful(bool). The weak actor identity
## prevents stale death notifications from a replaced or freed host actor.
func bind_enemy(key: StringName, actor: Node2D, active: Callable, peaceful: Callable, gfx_scale_x: Callable = Callable()) -> void:
	assert(not started and is_instance_valid(actor))
	assert(active.is_valid() and peaceful.is_valid())
	bindings[key] = {"actor": weakref(actor), "active": active, "peaceful": peaceful, "gfx_scale_x": gfx_scale_x}
	active.call(false)


func start() -> bool:
	if not is_node_ready() or started or restored_end or not settings.on_field:
		return false
	return _start_ready()


func start_spawn() -> bool:
	if not is_node_ready() or settings.on_field or restored_end or started:
		return false
	return _start_ready()


func _start_ready() -> bool:
	for key: StringName in keys:
		if not bindings.has(key) or not is_instance_valid(bindings[key].actor.get_ref()):
			return false
	started = true
	clock.start()
	_publish()
	return true


func notify_defeated(key: StringName, actor: Node2D) -> bool:
	if not started or not bindings.has(key) or bindings[key].actor.get_ref() != actor or not is_instance_valid(actor):
		return false
	var was_ended: bool = clock.ended
	var accepted: bool = clock.defeated(keys.find(key) + 1)
	if not was_ended and clock.ended:
		save_requested.emit({"isEnd": true})
	_publish()
	return accepted


## Forward the actor's post-damage ratio before its defeated signal when the
## same hit is lethal. Initial binding, healing and polling are not damage.
func notify_damaged(key: StringName, actor: Node2D, health_ratio: float) -> bool:
	if not started or not bindings.has(key) or bindings[key].actor.get_ref() != actor or not is_instance_valid(actor):
		return false
	var was_ended: bool = clock.ended
	var accepted: bool = clock.damaged(keys.find(key) + 1, health_ratio)
	if not was_ended and clock.ended:
		save_requested.emit({"isEnd": true})
	_publish()
	return accepted


func _registered(_phase: int, members: Array) -> void:
	for ref: Dictionary in members:
		var key: StringName = keys[int(ref.m_PathID) - 1]
		var actor: Node2D = bindings[key].actor.get_ref()
		if is_instance_valid(actor):
			member_registered.emit(key, actor)


func _arrival(_phase: int, members: Array) -> void:
	var batch := []
	for ref: Dictionary in members:
		var key: StringName = keys[int(ref.m_PathID) - 1]
		var kind := str(settings.arrival_kinds.get(String(key), "stamp"))
		var point: Vector2 = settings.placements.get(String(key), Vector2.ZERO)
		var ground_y := to_global(point).y
		point += Vector2(settings.arrival_offsets.get(kind, Vector2.ZERO))
		arrival_requested.emit(key, to_global(point), kind)
		var facing: Callable = bindings[key].gfx_scale_x
		batch.append({"key": key, "position": to_global(point), "sort_y": ground_y,
			"kind": kind, "gfx_scale_x": float(facing.call()) if facing.is_valid() else 1.0})
	wave_arrival_requested.emit(batch)


func _visible_phase(_phase: int, members: Array, peaceful: bool) -> void:
	for ref: Dictionary in members:
		var binding: Dictionary = bindings[keys[int(ref.m_PathID) - 1]]
		if is_instance_valid(binding.actor.get_ref()):
			binding.peaceful.call(peaceful)
			binding.active.call(true)


func _wild_phase(_phase: int, members: Array) -> void:
	for ref: Dictionary in members:
		var binding: Dictionary = bindings[keys[int(ref.m_PathID) - 1]]
		if is_instance_valid(binding.actor.get_ref()):
			binding.peaceful.call(false)


func _process(delta: float) -> void:
	var tick := Time.get_ticks_usec()
	var real_delta := delta / Engine.time_scale if Engine.time_scale > 0 else (tick - _last_tick) / 1000000.0
	_last_tick = tick
	if started:
		clock.advance(real_delta, delta, custom_time_scale)
		_publish()


func _publish() -> void:
	var state: Dictionary = clock.state
	if state.status != _last_status or state.phase != _last_phase or state.remaining != _last_remaining:
		_last_status = state.status
		_last_phase = state.phase
		_last_remaining = state.remaining
		state_changed.emit(state.status, state.phase, state.remaining)
