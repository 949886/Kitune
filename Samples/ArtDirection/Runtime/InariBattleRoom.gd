extends Node
## Source SpawnManager phases and DoorContactTrigger subscriptions. Real enemy
## defeated signals drive phase progression; timers never stand in for kills.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Door = preload("res://Samples/ArtDirection/Runtime/InariMachineDoor.gd")
const Encounter = preload("res://Samples/ArtDirection/Runtime/InariEncounterClock.gd")
const SpawnTrigger = preload("res://Samples/ArtDirection/Runtime/InariMonsterSpawnTrigger.gd")
const ArrivalBatch = preload("res://Samples/INARIMechanisms/Devices/ArrivalEffect/ArrivalBatch.tscn")
var stage: Node
var player: Node
var source: Dictionary
var doors: Dictionary = {}
var spawners: Dictionary = {}
var enemies: Dictionary = {}
var contacts: Array[Area2D] = []
var spawn_contacts: Array[Area2D] = []
var encounters: Dictionary = {}
var last_tick_usec := 0
var arrival_effects: Node2D


func status_text() -> String:
	for state: Dictionary in spawners.values():
		if state.status == "complete":
			return "敌人已清除 · 出口正在开启"
		if state.status in ["phase_delay", "spawning", "peaceful"]:
			return "下一波敌人即将出现"
		return (
			"第 %d / %d 波 · 剩余 %d 名敌人"
			% [int(state.phase) + 1, state.source.spawnDatas.size(), int(state.remaining)]
		)
	return ""


func configure(
	record: Dictionary, owner_stage: Node, actor: Node, rules: Dictionary, enable_encounter := true
) -> void:
	stage = owner_stage
	player = actor
	source = record
	last_tick_usec = Time.get_ticks_usec()
	for enemy: Node in stage.enemies:
		enemies[int(enemy.data.source_id)] = enemy
	for definition: Dictionary in source.doors:
		var door := Door.new()
		add_child(door)
		door.configure(definition, stage, player)
		doors[int(definition.id)] = door
	# A camera-only practice omits combat, not physical doors. Preserve each
	# native initial open/closed state without starting a disabled encounter.
	if not enable_encounter:
		set_process(false)
		return
	arrival_effects = ArrivalBatch.instantiate()
	arrival_effects.play_audio = false # The original stage already owns FMOD samples.
	stage.add_child(arrival_effects)
	if stage.has_method("sort_depth"):
		arrival_effects.z_index = stage.sort_depth(arrival_effects.source_group_order)
	for definition: Dictionary in source.spawners:
		var encounter := Encounter.new()
		encounter.configure(definition.fields, float(rules.spawn_delay))
		var state: Dictionary = encounter.state
		encounters[int(definition.id)] = encounter
		spawners[int(definition.id)] = state
		encounter.arrival_requested.connect(_arrival.bind(definition.fields))
		encounter.phase_visible.connect(_visible_phase)
		encounter.phase_wild.connect(_wild_phase)
		encounter.completed.connect(_complete.bind(state))
		for phase: Dictionary in definition.fields.spawnDatas:
			for ref: Dictionary in phase.EnemyPrefab:
				var enemy: Node = enemies[int(ref.m_PathID)]
				enemy.set_spawn_active(false)
				enemy.defeated.connect(_defeated.bind(int(definition.id), enemy))
		for selection: Dictionary in definition.fields.get("selectedEnemy", []):
			var enemy: Node = enemies[int(selection.enemyStateMachine.m_PathID)]
			enemy.damaged.connect(_damaged.bind(int(definition.id), enemy))
		if definition.fields.IsOnField:
			encounter.start()
	for definition: Dictionary in source.contacts:
		var area := _area(definition.trigger)
		area.body_entered.connect(_contact.bind(area, definition))
		contacts.append(area)
	for definition: Dictionary in source.spawn_triggers:
		var trigger := SpawnTrigger.new()
		stage.add_child(trigger)
		var id := int(definition.fields.monsterSpawner.m_PathID)
		trigger.configure(definition, player, bool(spawners[id].source.IsOnField))
		trigger.spawn_requested.connect(encounters[id].start)
		spawn_contacts.append(trigger)


func _area(data: Dictionary) -> Area2D:
	var area := Area2D.new()
	stage.add_child(area)
	area.transform = Assets.matrix(data.transform)
	area.collision_layer = 0
	area.collision_mask = Collision.PLAYER
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(data.size)
	shape.shape = rectangle
	shape.position = Assets.vec(data.offset)
	area.add_child(shape)
	return area


func _contact(body: Node, area: Area2D, record: Dictionary) -> void:
	if body != player or area.get_meta("consumed", false):
		return
	# Physics callback defers collision-layer changes to the next idle boundary.
	doors[int(record.fields.door.m_PathID)].call_deferred("notify")
	if record.fields.isOnce or record.fields.once:
		area.set_meta("consumed", true)
		area.set_deferred("monitoring", false)


func _arrival(phase: int, members: Array, fields: Dictionary) -> void:
	var batch := []
	arrival_effects.custom_time_scale = stage.combat_clock.scale_value
	var points: Array = fields.spawnDatas[phase].SpawnPoint
	var index := 0
	for ref: Dictionary in members:
		var enemy: Node = enemies[int(ref.m_PathID)]
		enemy.set_spawn_active(false)
		stage.audio.play_event("wave_rope" if enemy.data.kind == "EnemyRifleMan" else "wave_stamp", self)
		var rope: bool = enemy.data.kind == "EnemyRifleMan"
		var point: Vector2 = Vector2(points[index].x, -points[index].y) * 16.0
		var ground_y := point.y
		point.y -= float(fields.RifleManRopeYOffset if rope else fields.stampYOffset) * 16.0
		var facing: float = float(enemy.get("facing")) if enemy.get("facing") != null else 1.0
		if stage.get("data") is Dictionary and stage.data.has("source"):
			facing = arrival_effects.source_gfx_scale(stage.data.source, int(fields.m_GameObject.m_PathID), int(ref.m_PathID), facing)
		batch.append({"key": int(ref.m_PathID), "position": point, "sort_y": ground_y,
			"kind": "rope" if rope else "stamp", "gfx_scale_x": facing})
		index += 1
	arrival_effects.spawn_wave(batch)


func _visible_phase(_phase: int, members: Array, peaceful: bool) -> void:
	for ref: Dictionary in members:
		var enemy: Node = enemies[int(ref.m_PathID)]
		if peaceful:
			enemy.data.character_type = 0
		enemy.set_spawn_active(true)


func _wild_phase(_phase: int, members: Array) -> void:
	for ref: Dictionary in members:
		enemies[int(ref.m_PathID)].data.character_type = 2


func _complete(state: Dictionary) -> void:
	for ref: Dictionary in state.source.SpawnderDoors:
		if int(ref.m_PathID) != 0:
			doors[int(ref.m_PathID)].notify()


func _defeated(id: int, enemy: Node) -> void:
	encounters[id].defeated(int(enemy.data.source_id))


func _damaged(_amount: float, id: int, enemy: Node) -> void:
	var maximum := float(enemy.data.profile.f_maximumHealth)
	assert(maximum > 0)
	encounters[id].damaged(int(enemy.data.source_id), float(enemy.health) / maximum)


func _physics_process(delta: float) -> void:
	var tick := Time.get_ticks_usec()
	var real_delta := delta / Engine.time_scale if Engine.time_scale > 0 else (tick - last_tick_usec) / 1000000.0
	last_tick_usec = tick
	if is_instance_valid(arrival_effects):
		arrival_effects.custom_time_scale = stage.combat_clock.scale_value
	for encounter: RefCounted in encounters.values():
		encounter.advance(real_delta, delta, stage.combat_clock.scale_value)
