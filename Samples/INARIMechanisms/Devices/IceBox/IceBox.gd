@tool
extends "../../Core/DeviceHost.gd"
## One-shot source ElectroBox. Explicit callbacks keep all actor eligibility,
## frozen-state ownership and camera response inside the host project.
signal charge_started
signal discharged(affected: Array)
signal feedback_requested(kind: String)
const Native = preload("../../Core/Native/Runtime/InariIceBox.gd")
const Emitter = preload("../../Core/DeviceEmitter.gd")
const Burst = preload("../../Core/DeviceBurst.gd")
const Configuration = preload("IceBoxSettings.gd")
@export var settings: Configuration = preload("IceBoxSettings.tres")
@export_flags_2d_physics var hit_layers := 2
@export_flags_2d_physics var blocking_layers := 1
@export_flags_2d_physics var outline_occluder_layers := 1
@export_node_path("Node2D") var observer_path: NodePath
@export var observer_offset := Vector2.ZERO
@export var random_seed := 17
var mechanism: StaticBody2D
var observer: WeakRef
var targets: Dictionary = {}
var ambient_emitters: Array[Node] = []
var sorting: Callable = func(order: Array): return int(order[1])
var asset_folder := ""


func _ready() -> void:
	var record := prepare("IceBox")
	if Engine.is_editor_hint():
		return
	asset_folder = (Location as Script).resource_path.get_base_dir() + "/Assets/IceBox/"
	var ambient: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(asset_folder + "ambient.json")
	)
	for definition: Dictionary in ambient.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure_source(
			definition.duplicate(true),
			self,
			document.gravity,
			random_seed + ambient_emitters.size(),
			asset_folder
		)
		emitter.set_animation_visibility(definition.active)
		ambient_emitters.append(emitter)
		visuals_by_go[definition.go] = emitter
	record.fields.range = settings.radius_pixels / float(record.cell_size)
	record.fields.waitingTime = settings.charge_seconds
	record.fields.stunTime = settings.freeze_seconds
	record.fields.blinkIntervalMax = settings.blink_interval_max
	record.fields.blinkIntervalMin = settings.blink_interval_min
	record.fields.alphaTime = settings.outline_fade_seconds
	mechanism = Native.new()
	mechanism.use_host_adapter = true
	mechanism.observer_position = _observer_position
	mechanism.freeze_candidates = _candidates
	mechanism.apply_freeze = _freeze_target
	mechanism.blocking_mask = blocking_layers
	mechanism.ground_mask = outline_occluder_layers
	add_child(mechanism)
	mechanism.configure(record, self, null, document.rules.duplicate(true))
	mechanism.collision_layer = hit_layers
	mechanism.set_meta("device", self)
	mechanism.discharged.connect(func(affected: Array): discharged.emit(affected))
	if not observer_path.is_empty():
		bind_observer(get_node(observer_path), observer_offset)


func bind_observer(actor: Node2D, local_offset := Vector2.ZERO) -> void:
	observer = weakref(actor) if is_instance_valid(actor) else null
	observer_offset = local_offset


func register_target(actor: Node2D, freeze: Callable, eligible: Callable = Callable()) -> void:
	assert(is_instance_valid(actor) and freeze.is_valid())
	targets[actor.get_instance_id()] = {
		"actor": weakref(actor), "freeze": freeze, "eligible": eligible
	}


func unregister_target(actor: Node2D) -> void:
	targets.erase(actor.get_instance_id())


func _observer_position() -> Vector2:
	var actor: Node2D = observer.get_ref() if observer != null else null
	return actor.to_global(observer_offset) if is_instance_valid(actor) else Vector2.INF


func _candidates() -> Array:
	var result: Array[Node2D] = []
	for id: int in targets.keys():
		var binding: Dictionary = targets[id]
		var actor: Node2D = binding.actor.get_ref()
		if not is_instance_valid(actor):
			targets.erase(id)
		elif actor.is_inside_tree() and actor.can_process():
			if not binding.eligible.is_valid() or binding.eligible.call():
				result.append(actor)
	return result


func _freeze_target(actor: Node2D, seconds: float) -> bool:
	var binding: Dictionary = targets[actor.get_instance_id()]
	return binding.freeze.is_valid() and bool(binding.freeze.call(seconds))


func receive_hit(_interaction: int, _actor: Node = null, direction := 1.0) -> bool:
	var was_consumed: bool = mechanism.consumed
	# ElectroBox overrides the parent's attack-mask check. Attachment alone
	# must not call this; hosts call it on damage or a successful kunai teleport.
	var accepted: bool = mechanism.receive_study_hit({}, direction)
	if not was_consumed and mechanism.consumed:
		feedback_requested.emit("Attack")
		charge_started.emit()
	return accepted


func spawn_effect(_key: String, world_position: Vector2, _rotation: float) -> void:
	var burst := Burst.new()
	add_child(burst)
	burst.position = to_local(world_position)
	burst.configure(document.burst, document.gravity, asset_folder, random_seed)
