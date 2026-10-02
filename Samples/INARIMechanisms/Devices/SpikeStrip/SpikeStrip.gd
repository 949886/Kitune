@tool
extends "../../Core/DeviceHost.gd"
## Authored heat-trap art and one contiguous source SettedSpike polygon.
## Host callbacks decide invulnerability/death and apply damage; no player type,
## enemy group, global camera or health field is required by the device.
signal damaged(actor: Node2D, amount: float)
signal feedback_requested(kind: String)
const Native = preload("../../Core/Native/Runtime/StudyHazard.gd")
const Assets = preload("../../Core/Native/Runtime/OriginalAssets.gd")
const Emitter = preload("../../Core/DeviceEmitter.gd")
const Configuration = preload("SpikeSettings.gd")
@export var settings: Configuration = preload("SpikeSettings.tres")
@export_flags_2d_physics var actor_layers := 12
@export var random_seed := 17
var mechanism: Area2D
var targets: Dictionary = {}
var ambient_emitters: Array[Node] = []
var sorting: Callable = func(order: Array): return int(order[1])


func _ready() -> void:
	var record := prepare("SpikeStrip")
	if Engine.is_editor_hint():
		return
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/SpikeStrip/"
	var ambient: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(folder + "ambient.json")
	)
	for definition: Dictionary in ambient.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure_source(
			definition.duplicate(true),
			self,
			document.gravity,
			random_seed + ambient_emitters.size(),
			folder
		)
		emitter.set_animation_visibility(definition.active)
		ambient_emitters.append(emitter)
	mechanism = Native.new()
	mechanism.use_host_adapter = true
	mechanism.classify_actor = _classify_actor
	mechanism.damage_actor = _damage_actor
	mechanism.transform = Assets.matrix(record.transform)
	mechanism.collision_layer = 0
	mechanism.monitorable = false
	mechanism.configure_spike(settings.damage, null)
	mechanism.collision_mask = actor_layers
	for shape: Dictionary in record.shapes:
		for path: Array in shape.paths:
			var collider := CollisionPolygon2D.new()
			var polygon := PackedVector2Array()
			for point: Array in path:
				polygon.append(Assets.vec(point))
			collider.polygon = polygon
			collider.position = Assets.vec(shape.offset)
			mechanism.add_child(collider)
	mechanism.enemy_contact.connect(func(_actor: Node2D): feedback_requested.emit("Attack"))
	add_child(mechanism)


func register_player(actor: Node2D, damage: Callable, eligible: Callable = Callable()) -> void:
	_register(actor, Native.ContactRole.PLAYER, damage, eligible)


func register_enemy(actor: Node2D, damage: Callable, eligible: Callable = Callable()) -> void:
	_register(actor, Native.ContactRole.ENEMY, damage, eligible)


func _register(actor: Node2D, role: int, damage: Callable, eligible: Callable) -> void:
	assert(is_instance_valid(actor) and damage.is_valid())
	targets[actor.get_instance_id()] = {
		"actor": weakref(actor), "role": role, "damage": damage, "eligible": eligible
	}


func unregister_target(actor: Node2D) -> void:
	targets.erase(actor.get_instance_id())


func _physics_process(_delta: float) -> void:
	# Weak registrations cannot keep freed hosts alive. Prune even if no body
	# happens to be overlapping this frame.
	for id: int in targets.keys():
		if targets[id].actor.get_ref() == null:
			targets.erase(id)


func _classify_actor(actor: Node2D) -> int:
	# A host may change layers before Godot refreshes the overlap snapshot.
	if actor is CollisionObject2D and (actor.collision_layer & mechanism.collision_mask) == 0:
		return Native.ContactRole.NONE
	var binding: Dictionary = targets.get(actor.get_instance_id(), {})
	return int(binding.role) if not binding.is_empty() else Native.ContactRole.NONE


func _damage_actor(actor: Node2D, amount: float) -> void:
	var binding: Dictionary = targets.get(actor.get_instance_id(), {})
	if binding.is_empty() or not actor.can_process():
		return
	if binding.eligible.is_valid() and not binding.eligible.call():
		return
	if binding.damage.is_valid() and bool(binding.damage.call(amount)):
		damaged.emit(actor, amount)
