extends Node
## Resolves source observer component IDs per scene. No level coordinates or
## lever/platform pairings are encoded in gameplay code.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Platform = preload("res://Samples/ArtDirection/Runtime/InariMovingPlatform.gd")
const Lever = preload("res://Samples/ArtDirection/Runtime/InariLever.gd")
const Elevator = preload("res://Samples/ArtDirection/Runtime/InariElevator.gd")
const Portal = preload("res://Samples/ArtDirection/Runtime/InariScenePortal.gd")
const Arrival = preload("res://Samples/ArtDirection/Runtime/InariElevatorArrival.gd")
const IceBox = preload("res://Samples/ArtDirection/Runtime/InariIceBox.gd")
const Trial = preload("res://Samples/ArtDirection/Runtime/InariTimeTrial.gd")
const Battle = preload("res://Samples/ArtDirection/Runtime/InariBattleRoom.gd")
const Repeating = preload("res://Samples/ArtDirection/Runtime/InariRepeatingRoom.gd")

var platforms: Dictionary = {}
var levers: Array[Node] = []
var elevators: Array[Node] = []
var portals: Array[Node] = []
var arrival: Node
var battle: Node
var repeating: Node
var trial: Node
var ice_boxes: Array[Node] = []


func configure(stage: Node, player: CharacterBody2D) -> void:
	var rules: Dictionary = Assets.read_json(Assets.ROOT + "machinery.json")
	var scene: Dictionary = rules.levels.get(stage.data.source, {})
	if stage.scene_options.get("enable_repeating", false):
		var repeated: Dictionary = Assets.read_json(Assets.ROOT + "repeating_enemies.json")
		# A portal may carry the practice options into a different source level.
		# Only instantiate the spawner in its audited scene.
		if repeated.record.scene == stage.data.source and repeated.record.active and repeated.record.enabled:
			repeating = Repeating.new()
			add_child(repeating)
			repeating.configure(stage, player, repeated)
	if not scene.get("battle", {}).is_empty():
		battle = Battle.new()
		add_child(battle)
		battle.configure(
			scene.battle,
			stage,
			player,
			rules.battle_rules,
			stage.scene_options.get("enable_battle", false)
		)
	if not scene.get("trials", {}).is_empty() and stage.scene_options.get("enable_trial", false):
		trial = Trial.new()
		add_child(trial)
		trial.configure(scene.trials, stage, player, rules.trial_rules)
	for record: Dictionary in scene.get("ice_boxes", []):
		var ice := IceBox.new()
		stage.add_child(ice)
		ice.configure(record, stage, player, rules.ice_rules)
		ice_boxes.append(ice)
	for record: Dictionary in scene.get("platforms", []):
		var platform := Platform.new()
		platform.name = "NativePlatform_" + str(record.go)
		platform.configure(record, player, stage.visual_instances)
		stage.add_child(platform)
		stage.combat_clock.subscribe(platform)
		platforms[str(record.id)] = platform
		for collider: Dictionary in record.get("child_colliders", []):
			var body: Node = stage._build_collider(collider)
			body.reparent(platform, true)
	for record: Dictionary in scene.get("levers", []):
		var lever := Lever.new()
		lever.name = "NativeLever_" + str(record.go)
		lever.configure(record, stage, platforms)
		stage.add_child(lever)
		levers.append(lever)
	for record: Dictionary in scene.get("elevators", []):
		var elevator := Elevator.new()
		stage.add_child(elevator)
		elevator.configure(record, stage, player, platforms, rules.elevator_rules)
		elevators.append(elevator)
	for record: Dictionary in scene.get("scene_moves", []):
		if not record.available:
			continue
		assert(
			not record.fields.maintainInputOnTransition,
			"Input-maintaining portals require an additional adapter"
		)
		var portal := Portal.new()
		stage.add_child(portal)
		portal.configure(record, player)
		portal.requested.connect(stage.scene_change_requested.emit)
		portals.append(portal)
	if not scene.get("arrival", {}).is_empty():
		arrival = Arrival.new()
		stage.add_child(arrival)
		arrival.configure(scene.arrival, stage, player)


func satisfies(condition: Dictionary) -> bool:
	match condition.get("kind", ""):
		"camera_zone":
			var stage: Node = get_parent()
			if not is_instance_valid(stage.camera_zones):
				return false
			for zone: Node in stage.camera_zones.zones:
				if int(zone.source.go) == int(condition.go):
					return zone.consumed if condition.get("exited", false) else zone.entries > 0
		"trial_reward":
			return (
				is_instance_valid(trial)
				and trial.rewards.all(func(reward): return reward.collected)
			)
		"ice_fired":
			for ice: Node in ice_boxes:
				if int(ice.source.go) == int(condition.go):
					return (
						ice.fired
						and ice.affected.size() >= int(condition.get("minimum_affected", 0))
					)
		"battle_complete":
			return (
				is_instance_valid(battle)
				and battle.spawners[int(condition.id)].status == "complete"
			)
		"repeat_count":
			return is_instance_valid(repeating) and repeating.replacement_count >= int(condition.minimum)
		"lever":
			for lever: Node in levers:
				if int(lever.source.go) == int(condition.go):
					return lever.switched_on
		"arrival":
			var platform: Node = platforms.get(str(condition.id))
			return platform != null and platform.arrival_count > 0
		"elevator_open":
			for elevator: Node in elevators:
				if int(elevator.source.go) == int(condition.go):
					return elevator.consumed and not elevator.doors_closed
		"elevator_started":
			for elevator: Node in elevators:
				if int(elevator.source.go) == int(condition.go):
					return elevator.consumed
	return condition.is_empty()
