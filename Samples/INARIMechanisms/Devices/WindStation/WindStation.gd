@tool
extends "../../Core/DeviceHost.gd"
## A station grants requests, never edits host stats or installs a controller.
## Each instance owns its source Animator, cooldown, one-time stamina and audio.
signal began
signal activated(actor: Node)
signal cooled
signal cancelled
signal stamina_requested(actor: Node, amount: float)
signal story_heal_requested(actor: Node, amount: int)
signal stamina_feedback_requested(actor: Node)
const Native = preload("../../Core/Native/Runtime/InariWindTrigger.gd")
const Animator = preload("../../Core/Native/Runtime/InariWindAnimation.gd")
const Configuration = preload("WindStationSettings.gd")
@export var settings: Configuration = preload("WindStationSettings.tres")
@export_flags_2d_physics var actor_layers := 4
var mechanism: Area2D
var animator: Node
var actor_ref: WeakRef
var request_buff: Callable
var spawning: Callable
var eligible: Callable


func _ready() -> void:
	var record := prepare("WindStation")
	if Engine.is_editor_hint():
		return
	var visual: Node2D = visuals_by_go[document.animated_visual]
	animator = Animator.new()
	add_child(animator)
	animator.configure(document.controller, visual, visual.data.material)
	record.size = [settings.trigger_size.x, settings.trigger_size.y]
	record.offset = [settings.trigger_offset.x, settings.trigger_offset.y]
	record.cooldown = settings.cooldown_seconds
	record.stamina = settings.stamina_amount
	mechanism = Native.new()
	mechanism.use_host_adapter = true
	mechanism.accept_actor = _accept_actor
	mechanism.is_spawning = _is_spawning
	mechanism.apply_buff = _apply_buff
	# Source waits until Animator has left Ready before completing cooldown.
	mechanism.can_finish_cooldown = animator.has_left_ready
	mechanism.audio = audio
	mechanism.stamina_once = settings.stamina_already_granted
	add_child(mechanism)
	mechanism.configure(record, settings.story_heal_amount)
	mechanism.collision_mask = actor_layers
	mechanism.began.connect(animator.set_trigger.bind("On"))
	mechanism.cooled.connect(animator.set_trigger.bind("Off"))
	mechanism.cancelled.connect(animator.reset)
	mechanism.began.connect(began.emit)
	mechanism.activated.connect(activated.emit)
	mechanism.cooled.connect(cooled.emit)
	mechanism.cancelled.connect(cancelled.emit)
	mechanism.stamina_requested.connect(stamina_requested.emit)
	mechanism.healing_requested.connect(story_heal_requested.emit)
	mechanism.stamina_feedback_requested.connect(stamina_feedback_requested.emit)


func bind_actor(
	actor: Node2D,
	receive_buff: Callable,
	is_spawning: Callable = Callable(),
	can_receive: Callable = Callable()
) -> void:
	# Rebinding cancels a deferred request; it cannot transfer to the new actor.
	if is_instance_valid(mechanism):
		mechanism.cancel_pending()
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	request_buff = receive_buff
	spawning = is_spawning
	eligible = can_receive


func unbind_actor() -> void:
	bind_actor(null, Callable())


func has_granted_stamina() -> bool:
	return is_instance_valid(mechanism) and mechanism.stamina_once


func is_cooling() -> bool:
	return is_instance_valid(mechanism) and mechanism.cooling


func _accept_actor(actor: Node) -> bool:
	if actor_ref == null or actor_ref.get_ref() != actor or not request_buff.is_valid():
		return false
	if actor is CollisionObject2D and (actor.collision_layer & mechanism.collision_mask) == 0:
		return false
	return actor.can_process() and (not eligible.is_valid() or bool(eligible.call()))


func _is_spawning(_actor: Node) -> bool:
	return spawning.is_valid() and bool(spawning.call())


func _apply_buff(_actor: Node) -> void:
	request_buff.call()
