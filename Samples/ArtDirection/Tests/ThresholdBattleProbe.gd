extends SceneTree
## Native adapter fixture with audited level8 fields. Actor stubs verify the
## post-damage ratio/death signal wiring; this is not SwordMan/SpikeMan AI or
## the source room's final Timeline, which remain separate work.
const Battle = preload("res://Samples/ArtDirection/Runtime/InariBattleRoom.gd")

class Member extends Node2D:
	signal damaged(amount: float)
	signal defeated
	var data: Dictionary
	var health := 100.0
	var active := false
	func set_spawn_active(value: bool) -> void:
		active = value
	func damage(amount: float) -> void:
		health = maxf(0, health - amount)
		damaged.emit(amount)
		if health == 0:
			active = false
			defeated.emit()

class AudioLog extends Node:
	var calls := 0
	func play_event(_event: String, _owner: Node) -> void:
		calls += 1

class Stage extends Node2D:
	var enemies: Array[Node] = []
	var audio := AudioLog.new()
	var combat_clock := {"scale_value": 1.0}


func _initialize() -> void:
	call_deferred("run")


func arrival(clock: RefCounted) -> void:
	clock.advance(0, 0, 1)
	clock.advance(1.21, 1.21, 1)
	clock.advance(0.26, 0.26, 1)
	assert(clock.state.status == "fighting")


func run() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://Samples/INARIMechanisms/Assets/ThresholdEncounter/device.json"))
	var source: Dictionary = evidence.records.level8_11829
	var fields: Dictionary = source.source.fields.duplicate(true)
	# This fixture exercises health routing, not door subscriptions/Timeline.
	fields.SpawnderDoors = []
	var fixture := Stage.new()
	root.add_child(fixture)
	fixture.add_child(fixture.audio)
	var members := {}
	for key: String in source.enemy_keys:
		var actor := Member.new()
		var id := int(source.enemy_keys[key])
		actor.data = {"source_id": id, "kind": source.enemy_types[key],
			"character_type": 2, "profile": {"f_maximumHealth": 100.0}}
		fixture.add_child(actor)
		fixture.enemies.append(actor)
		members[id] = actor
	var battle := Battle.new()
	fixture.add_child(battle)
	var player := Node2D.new()
	fixture.add_child(player)
	battle.configure({"doors": [], "contacts": [], "spawn_triggers": [],
		"spawners": [{"id": int(source.source.component_id), "fields": fields}]}, fixture, player, {"spawn_delay": 1.2})
	battle.set_physics_process(false)
	var clock: RefCounted = battle.encounters[int(source.source.component_id)]
	assert(clock.start())
	arrival(clock)
	for phase in 2:
		for ref: Dictionary in fields.spawnDatas[phase].EnemyPrefab:
			members[int(ref.m_PathID)].damage(100)
		assert(clock.state.phase == phase + 1)
		clock.advance(0.26, 0, 1)
		arrival(clock)
	var selected := int(fields.selectedEnemy[0].enemyStateMachine.m_PathID)
	var boss: Member = members[selected]
	boss.damage(24)
	assert(clock.state.phase == 2 and boss.health == 76)
	boss.damage(1)
	assert(clock.state.phase == 3 and clock.state.remaining == 3 and boss.active)
	clock.advance(0.26, 0, 1)
	arrival(clock)
	for ref: Dictionary in fields.spawnDatas[3].EnemyPrefab:
		members[int(ref.m_PathID)].damage(100)
	assert(clock.state.remaining == 1 and not clock.ended)
	boss.damage(75)
	assert(clock.ended and not boss.active)
	clock.advance(0.51, 0, 0)
	assert(clock.state.status == "complete" and fixture.audio.calls == 8)
	fixture.queue_free()
	await process_frame
	await process_frame
	print("NATIVE_THRESHOLD_BATTLE_PASS")
	quit()
