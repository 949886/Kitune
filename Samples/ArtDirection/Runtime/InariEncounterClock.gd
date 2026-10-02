extends RefCounted
## SpawnManager's death-count waves and selectedEnemy health thresholds.
## The owner supplies entity hooks;
## this clock never fabricates deaths or looks up a player/door in the tree.
## Realtime phase/end waits are separate from scaled arrival/peaceful waits.
signal phase_registered(index: int, members: Array)
signal arrival_requested(index: int, members: Array)
signal phase_visible(index: int, members: Array, peaceful: bool)
signal phase_wild(index: int, members: Array)
signal completed
var state: Dictionary
var realtime := 0.0
var game_time := 0.0
var ended := false
var counted: Dictionary = {}
var registered: Dictionary = {}
var thresholds: Dictionary = {}
var thresholds_consumed: Dictionary = {}
var peaceful_waits: Array[Dictionary] = []


func configure(fields: Dictionary, arrival_delay: float, restored_end := false) -> void:
	assert(not fields.spawnDatas.is_empty())
	state = {"source": fields.duplicate(true), "phase": 0, "remaining": 0,
		"status": "complete" if restored_end else "waiting", "due": INF,
		"spawn_delay": arrival_delay}
	realtime = 0.0
	game_time = 0.0
	ended = restored_end
	counted.clear()
	registered.clear()
	thresholds.clear()
	thresholds_consumed.clear()
	for selection: Dictionary in fields.get("selectedEnemy", []):
		var key := int(selection.enemyStateMachine.m_PathID)
		assert(not thresholds.has(key), "Each source selection must identify one damage listener")
		thresholds[key] = float(selection.hpRatio)
	peaceful_waits.clear()


func members() -> Array:
	return state.source.spawnDatas[state.phase].EnemyPrefab


func start() -> bool:
	if ended or state.status != "waiting":
		return false
	state.remaining = members().size()
	_activate(not bool(state.source.IsOnField))
	return true


func _activate(arrival: bool) -> void:
	var phase := int(state.phase)
	var current_members := members().duplicate(true)
	# NextPhase has already included carried survivors in remaining. Activating
	# its new members must not reset that count or resurrect defeated survivors.
	state.status = "spawn_wait" if arrival else "fighting"
	state.due = INF
	if arrival:
		arrival_requested.emit(phase, current_members.duplicate(true))
	for ref: Dictionary in current_members:
		registered[int(ref.m_PathID)] = true
	phase_registered.emit(phase, current_members.duplicate(true))
	if not arrival:
		phase_visible.emit(phase, current_members.duplicate(true), false)
	# A source empty wave has no onDead event: it does not auto-complete.


func defeated(key: int) -> bool:
	# InitEvent leaves earlier death listeners subscribed. A surviving selected
	# enemy can die during the next phase's realtime delay or after its arrival.
	if ended or counted.has(key) or not registered.has(key):
		return false
	counted[key] = true
	state.remaining -= 1
	if state.remaining > 0:
		return true
	_next_phase(0)
	return true


## Called for a real post-damage health ratio, not by polling health each frame.
## Reaching the threshold removes that listener before progressing the wave.
## The selected enemy remains alive and its later death is still counted.
func damaged(key: int, health_ratio: float) -> bool:
	if ended or not registered.has(key) or counted.has(key) or not thresholds.has(key) or thresholds_consumed.has(key):
		return false
	if not is_finite(health_ratio) or health_ratio > float(thresholds[key]):
		return false
	thresholds_consumed[key] = true
	# Source remainingEnemyCount = currentWave.Count - dieMonsterCount, then
	# forces CountDieEnemy's phase transition. This is not a fabricated death:
	# NextPhase starts its counter negative to carry every surviving old member.
	_next_phase(int(state.remaining))
	return true


func _next_phase(survivors: int) -> void:
	if int(state.phase) + 1 < state.source.spawnDatas.size():
		state.phase += 1
		state.remaining = members().size() + survivors
		state.status = "phase_delay"
		state.due = realtime + float(state.source.PhaseChangingTime)
	else:
		# Source isEnd/save dirty becomes true before the final door delay.
		# A selection configured on the final wave also ends immediately at its
		# threshold in the C# code, even if that enemy is alive. Keep this edge.
		ended = true
		state.remaining = 0
		state.status = "end_delay"
		state.due = realtime + float(state.source.EndTime)


func advance(real_delta: float, scaled_delta: float, custom_scale: float) -> void:
	realtime += maxf(real_delta, 0.0)
	game_time += maxf(scaled_delta, 0.0)
	# SpawnRoutine coroutines retain their own captured phase. Killing a wave
	# during its peaceful wait must not apply that wait to the next wave.
	for index in range(peaceful_waits.size() - 1, -1, -1):
		var pending := peaceful_waits[index]
		if game_time >= float(pending.due):
			peaceful_waits.remove_at(index)
			if state.phase == pending.phase and state.status == "peaceful":
				state.status = "fighting"
				state.due = INF
			phase_wild.emit(pending.phase, pending.members)
	if state.status == "spawn_wait":
		# Only entering the 1.2 s wait is gated by the custom hit-stop scale.
		# A later hit-stop does not restart/freeze Unity's WaitForSeconds.
		if custom_scale == 0.0:
			return
		state.status = "spawning"
		state.due = game_time + float(state.spawn_delay)
	var now := game_time if state.status == "spawning" else realtime
	if now < float(state.due):
		return
	match state.status:
		"phase_delay":
			_activate(true)
		"spawning":
			state.status = "peaceful"
			state.due = INF
			peaceful_waits.append({"phase": state.phase,
				"members": members().duplicate(true), "due": game_time + float(state.source.waitingTime)})
			phase_visible.emit(state.phase, members().duplicate(true), true)
		"end_delay":
			state.status = "complete"
			state.due = INF
			completed.emit()
