@tool
extends "../../Core/DeviceHost.gd"
## Standalone source endpoint. Host input explicitly calls interact(actor).
signal proximity_changed(actor: Node, nearby: bool)
signal used(actor: Node)
const Native = preload("../../Core/Native/Runtime/InariTrialTerminal.gd")
const Digits = preload("../../Core/Native/Runtime/InariTimerDigits.gd")
@export_enum("TimerStart", "TimerFinish") var asset_kind := "TimerStart"
@export_flags_2d_physics var actor_layers := 4
var mechanism: Area2D
var display := Digits.new()
var actor_ref: WeakRef
var eligible: Callable
var use_request: Callable
var stage: Node:
	get:
		return self
var player: Node:
	get:
		return actor_ref.get_ref() if actor_ref != null else null


func _ready() -> void:
	var record := prepare(asset_kind)
	display.configure(record.digits, visuals_by_go)
	display.update(document.duration, true)
	if Engine.is_editor_hint():
		return
	animation.configure(document.default_tracks, visuals_by_go)
	mechanism = Native.new()
	mechanism.use_host_adapter = true
	mechanism.accept_actor = _accept_actor
	mechanism.request_use = _use
	mechanism.actor_layers = actor_layers
	add_child(mechanism)
	mechanism.configure(record, self)
	mechanism.proximity_changed.connect(proximity_changed.emit)


func bind_actor(actor: Node2D, can_use: Callable = Callable()) -> void:
	if is_instance_valid(mechanism):
		mechanism._exit(player)
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_use


func _accept_actor(actor: Node) -> bool:
	return (
		is_instance_valid(actor)
		and actor == player
		and actor.can_process()
		and actor is CollisionObject2D
		and (actor.collision_layer & actor_layers) != 0
		and (not eligible.is_valid() or bool(eligible.call()))
	)


func _use(actor: Node) -> bool:
	if use_request.is_valid() and not bool(use_request.call(actor)):
		return false
	disable()
	used.emit(actor)
	return true


func interact(actor: Node) -> bool:
	return is_instance_valid(mechanism) and mechanism.interact(actor)


func disable() -> void:
	mechanism.disable()


func is_available() -> bool:
	return is_instance_valid(mechanism) and mechanism.available


func play(state_name: String) -> void:
	mechanism.play(state_name)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		display.step(delta)
