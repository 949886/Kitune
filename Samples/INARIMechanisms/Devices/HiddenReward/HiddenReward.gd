@tool
extends "../../Core/DeviceHost.gd"
## Once-only pickup with independent homing fragments. Player stats, inventory,
## existing buff renewal and persistence remain explicit host responsibilities.
signal reward_granted(actor: Node2D, amount: int, reward_id: String)
signal renew_existing_buff_requested(actor: Node2D)
signal currency_requested(actor: Node2D, amount: int)
signal fragments_finished(received_count: int)
signal lights_changed(source_lights: Dictionary)
const Native = preload("../../Core/Native/Runtime/InariTrialReward.gd")
const Emitter = preload("../../Core/DeviceEmitter.gd")
const Distortion = preload("../../Core/DeviceDistortion.gd")
const Configuration = preload("RewardSettings.gd")
@export var settings: Configuration = preload("RewardSettings.tres")
@export var reward_id := ""
@export_flags_2d_physics var actor_layers := 4
@export var random_seed := 17
@export_range(0, 5, 0.01, "or_greater") var motion_time_scale := 1.0
var mechanism: Area2D
var actor_ref: WeakRef
var target_ref: WeakRef
var eligible: Callable
var rules: Dictionary
var ambient_emitters: Array[Node] = []
var completion_sent := false
var fragment_emitters: Array[Node] = []
var fragments_cancelled := false
# Context for the shared native reward; it contains only local rendering/audio
# and an explicitly bound player, never a global scene or Rossi controller.
var stage: Node:
	get:
		return self
var player: Node2D:
	get:
		return actor_ref.get_ref() if actor_ref != null else null
var sorting: Callable = func(order: Array): return int(order[1])


func _make_visual(record: Dictionary) -> Node2D:
	return Distortion.new() if record.has("square_distortion") else super._make_visual(record)


func _ready() -> void:
	var record := prepare("HiddenReward")
	if Engine.is_editor_hint():
		return
	rules = document.rules.duplicate(true)
	rules.charge_value = settings.currency_per_fragment
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/HiddenReward/"
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
		emitter.set_animation_visibility(definition.active and not settings.initially_collected)
		for charge: Dictionary in record.charges:
			if int(charge.go) in definition.ancestor_gos.map(func(id): return int(id)):
				var visual: Node2D = visuals_by_go[charge.go]
				var inverse: Transform2D = visual.transform.affine_inverse()
				emitter.frame_transform = func():
					return global_transform * visual.transform * inverse
				fragment_emitters.append(emitter)
				break
		visuals_by_go[definition.go] = emitter
		ambient_emitters.append(emitter)
	animation.configure(document.default_tracks, visuals_by_go)
	mechanism = Native.new()
	mechanism.use_host_adapter = true
	mechanism.initially_collected = settings.initially_collected
	mechanism.accept_actor = _accept_actor
	mechanism.actor_alive = _actor_alive
	mechanism.target_position = _target_position
	mechanism.actor_layers = actor_layers
	mechanism.host_units = document.units
	mechanism.host_time_scale = motion_time_scale
	mechanism.random.seed = random_seed
	mechanism.collected_event.connect(_collected)
	mechanism.currency_requested.connect(currency_requested.emit)
	mechanism.lights_changed.connect(lights_changed.emit)
	add_child(mechanism)
	mechanism.configure(record, self)
	completion_sent = settings.initially_collected
	if not settings.initially_collected:
		lights_changed.emit(get_light_state())


## Bind before first overlap. The aim node usually is the actor's body shape.
## Rebinding after collection cancels remaining fragments, never transfers them.
func bind_actor(actor: Node2D, target: Node2D, can_receive: Callable = Callable()) -> void:
	assert(is_instance_valid(actor) and (actor == target or actor.is_ancestor_of(target)))
	unbind_actor()
	actor_ref = weakref(actor)
	target_ref = weakref(target)
	eligible = can_receive


func unbind_actor() -> void:
	if is_instance_valid(mechanism) and mechanism.collected:
		fragments_cancelled = true
		for charge: Node in mechanism.charges.values():
			if not charge.finished:
				charge.cancel()
	actor_ref = null
	target_ref = null
	eligible = Callable()


func _actor_alive() -> bool:
	var actor := player
	return (
		is_instance_valid(actor)
		and actor.can_process()
		and target_ref != null
		and is_instance_valid(target_ref.get_ref())
		and (not eligible.is_valid() or bool(eligible.call()))
	)


func _accept_actor(actor: Node2D) -> bool:
	return actor == player and _actor_alive() and (actor.collision_layer & actor_layers) != 0


func _target_position() -> Vector2:
	return target_ref.get_ref().global_position


func _collected(actor: Node2D) -> void:
	renew_existing_buff_requested.emit(actor)
	reward_granted.emit(actor, settings.reward_amount, reward_id)


func is_collected() -> bool:
	return is_instance_valid(mechanism) and mechanism.collected


func received_fragment_count() -> int:
	var count := 0
	for charge: Node in mechanism.charges.values():
		if charge.received:
			count += 1
	return count


func get_light_state() -> Dictionary:
	return mechanism.lights.duplicate(true) if is_instance_valid(mechanism) else {}


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(mechanism):
		return
	mechanism.host_time_scale = maxf(0, motion_time_scale)
	if mechanism.collected and not _actor_alive():
		fragments_cancelled = true
		for charge: Node in mechanism.charges.values():
			if not charge.finished:
				charge.cancel()
	var finished: bool = mechanism.collected
	for charge: Node in mechanism.charges.values():
		charge.on_source_time_scale(mechanism.host_time_scale)
		finished = finished and charge.finished
	if finished and not completion_sent:
		completion_sent = true
		fragments_finished.emit(received_fragment_count())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(mechanism):
		return
	# Capturing a fragment only hides its SpriteRenderer in the source; child
	# particles remain active until its GameObject is disabled by actor death.
	var active: bool = (
		mechanism.collected
		and not settings.initially_collected
		and not fragments_cancelled
		and _actor_alive()
	)
	for emitter: Node in fragment_emitters:
		emitter.set_animation_visibility(active)
