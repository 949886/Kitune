extends Area2D
## InteractableObjectTrigger / MoveElevator. The shipped button is consumed
## after use; arrival opens the gates but does not re-enable this trigger.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Animator = preload("res://Samples/ArtDirection/Runtime/InariMechanismAnimator.gd")

var source: Dictionary
var stage: Node
var player: CharacterBody2D
var targets: Array[Node] = []
var gates: Array[StaticBody2D] = []
var button_animation := Animator.new()
var door_animation := Animator.new()
var station_animations: Dictionary = {}
var consumed := false
var doors_closed := false
var clock := 0.0
var release_at := INF
var release_delay := 0.0
var steam_due: Dictionary = {}
var prompt := "F / Y  启动电梯"
## Explicit host integration keeps controller fields and projectile ownership
## out of the copied device. The native demo retains its original player path.
signal interaction_available(actor: Node, available: bool)
signal projectile_recall_requested(actor: Node)
signal gates_changed(closed: bool)
var use_host_adapter := false
var actor_eligible: Callable
var host_solid_layers := 1
var host_actor_layers := 4


func configure(
	record: Dictionary,
	owner_stage: Node,
	actor: CharacterBody2D,
	platforms: Dictionary,
	rules: Dictionary
) -> void:
	source = record
	stage = owner_stage
	player = actor
	release_delay = float(rules.door_release_delay)
	transform = Assets.matrix(record.trigger.transform)
	collision_layer = 0
	collision_mask = host_actor_layers if use_host_adapter else Collision.PLAYER
	monitorable = false
	add_child(_box(record.trigger))
	for id: String in record.targets:
		var platform: Node = platforms[id]
		targets.append(platform)
		platform.started.connect(_started.bind(platform))
		platform.arrived.connect(_arrived.bind(platform))
		var pair := {}
		for key: String in ["start_animation", "end_animation"]:
			var animation := Animator.new()
			add_child(animation)
			animation.configure(platform.source.get(key, {}), stage)
			pair[key] = animation
		station_animations[id] = pair
	assert(targets.size() == 1, "A moving cabin trigger must have one owning elevator")
	# Gameplay shapes follow the cabin; visuals retain their sorting parents.
	reparent(targets[0], true)
	for data: Dictionary in record.doors:
		var gate := StaticBody2D.new()
		stage.add_child(gate)
		gate.transform = Assets.matrix(data.transform)
		gate.add_child(_box(data))
		gate.collision_layer = 0
		gate.collision_mask = host_actor_layers if use_host_adapter else Collision.PLAYER
		gate.set_meta("source_layer", "Door")
		gate.set_meta("source_go", data.go)
		gate.set_meta("climbable", true)
		gate.reparent(targets[0], true)
		gates.append(gate)
	add_child(button_animation)
	button_animation.configure(record.button_animation, stage)
	add_child(door_animation)
	door_animation.configure(record.door_animation, stage)
	body_entered.connect(_enter)
	body_exited.connect(_exit)
	process_physics_priority = 200


func _box(data: Dictionary) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(data.size)
	shape.shape = rectangle
	shape.position = Assets.vec(data.offset)
	return shape


func _enter(body: Node) -> void:
	if body == player and not consumed:
		if use_host_adapter:
			interaction_available.emit(body, can_interact(body))
		else:
			player.interaction_target = self


func _exit(body: Node) -> void:
	if body == player:
		if use_host_adapter:
			interaction_available.emit(body, false)
		elif player.interaction_target == self:
			player.interaction_target = null


func can_interact(actor: Node) -> bool:
	if consumed or not is_instance_valid(player) or actor != player:
		return false
	if use_host_adapter:
		return (
			player.can_process()
			and overlaps_body(player)
			and (player.collision_layer & collision_mask) != 0
			and (not actor_eligible.is_valid() or bool(actor_eligible.call()))
		)
	return player.interaction_target == self and has_overlapping_bodies()


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	button_animation.trigger("Interact")
	if use_host_adapter:
		interaction_available.emit(actor, false)
	else:
		player.interaction_target = null
	consumed = true
	set_deferred("monitoring", false)
	button_animation.trigger("On")
	door_animation.trigger("Close")
	_set_gates(true)
	if use_host_adapter:
		projectile_recall_requested.emit(actor)
	else:
		player._clear_projectile()
	for platform: Node in targets:
		platform.activate()
	return true


func _set_gates(closed: bool) -> void:
	doors_closed = closed
	for gate: StaticBody2D in gates:
		if use_host_adapter:
			gate.collision_layer = host_solid_layers if closed else 0
			continue
		gate.collision_layer = (
			(
				Collision.SOLID
				| Collision.PROJECTILE_SURFACE
				| Collision.RAY_SURFACE
				| Collision.STUCK_SURFACE
			)
			if closed
			else 0
		)
	gates_changed.emit(closed)


func _started(platform: Node) -> void:
	steam_due[str(platform.source.id)] = clock + float(platform.source.fields.WaitTime)
	# Source ElevatorPlatform suppresses the ordinary MovingPlatform sound.
	stage.audio.play_event("elevator_steam", platform)
	stage.audio.play_event("elevator", platform)


func _arrived(platform: Node) -> void:
	station_animations[str(platform.source.id)].end_animation.trigger("On")
	door_animation.trigger("Open")
	release_at = clock + release_delay
	stage.audio.stop_events(platform)


func _physics_process(delta: float) -> void:
	clock += delta
	for id: String in steam_due.keys():
		if clock >= float(steam_due[id]):
			station_animations[id].start_animation.trigger("On")
			steam_due.erase(id)
	if clock >= release_at:
		release_at = INF
		_set_gates(false)
