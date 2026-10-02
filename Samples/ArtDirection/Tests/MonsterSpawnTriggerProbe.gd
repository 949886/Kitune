extends SceneTree
## Adapter fixture: real physics entry into the exported level6 trigger drives
## InariBattleRoom's native spawning path. Member stubs verify activation/audio
## wiring; original AI/combat is covered separately by BattleRoomProbe.
const Battle = preload("res://Samples/ArtDirection/Runtime/InariBattleRoom.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

class Member extends Node2D:
	signal defeated
	var data: Dictionary
	var active := false
	func set_spawn_active(value: bool) -> void:
		active = value

class AudioLog extends Node:
	var events: Array[String] = []
	func play_event(event: String, _owner: Node) -> void:
		events.append(event)

class Stage extends Node2D:
	var enemies: Array[Node] = []
	var audio := AudioLog.new()
	var combat_clock := {"scale_value": 1.0}


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://Samples/INARIMechanisms/Assets/MonsterSpawnTrigger/device.json"))
	var source: Dictionary = exported.records.level6_11494
	var fixture := Stage.new()
	root.add_child(fixture)
	fixture.add_child(fixture.audio)
	var player := CharacterBody2D.new()
	player.collision_layer = Collision.PLAYER
	player.collision_mask = 0
	player.position = Vector2(2000, 2000)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 24)
	shape.shape = rectangle
	player.add_child(shape)
	fixture.add_child(player)
	var fields: Dictionary = source.target.fields.duplicate(true)
	# This fixture tests trigger-to-spawner routing, not the source door set.
	fields.SpawnderDoors = []
	for id: String in source.target.member_kinds:
		var member := Member.new()
		member.data = {"source_id": int(id), "kind": source.target.member_kinds[id], "character_type": 2}
		fixture.add_child(member)
		fixture.enemies.append(member)
	var battle := Battle.new()
	fixture.add_child(battle)
	var spawner_id := int(source.record.fields.monsterSpawner.m_PathID)
	battle.configure({"doors": [], "contacts": [], "spawners": [{"id": spawner_id, "fields": fields}],
		"spawn_triggers": [source.record.duplicate(true)]}, fixture, player, {"spawn_delay": 1.2})
	assert(battle.spawn_contacts.size() == 1 and fixture.enemies.all(func(e): return not e.active))
	var trigger: Area2D = battle.spawn_contacts[0]
	var host := {"loading": true}
	trigger.is_loading = func(): return host.loading
	var center: Vector2 = Assets.matrix(source.record.trigger.transform) * Assets.vec(source.record.trigger.offset)
	player.position = center
	await frames(4)
	assert(trigger.waits.is_empty())
	host.loading = false
	await frames(4)
	assert(trigger.waits.is_empty())
	player.position = Vector2(2000, 2000)
	await frames(3)
	player.position = center
	await frames(4)
	assert(trigger.waits.size() == 1 and battle.spawners[spawner_id].status == "waiting")
	await frames(85)
	assert(trigger.activated and not trigger.object_active)
	assert(battle.spawners[spawner_id].status in ["spawn_wait", "spawning"])
	assert(fixture.enemies.all(func(e): return not e.active))
	await frames(100)
	var first_count: int = fields.spawnDatas[0].EnemyPrefab.size()
	assert(battle.spawners[spawner_id].status == "fighting")
	assert(fixture.enemies.filter(func(e): return e.active).size() == first_count)
	assert(fixture.audio.events.size() == first_count)
	assert(fixture.enemies.filter(func(e): return e.active).all(func(e): return e.data.character_type == 2))
	fixture.queue_free()
	await frames(3)
	print("NATIVE_MONSTER_SPAWN_TRIGGER_PASS")
	quit()
