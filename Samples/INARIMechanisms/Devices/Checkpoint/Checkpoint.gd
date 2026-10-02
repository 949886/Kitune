@tool
extends "../../Core/DeviceHost.gd"
## One-shot source trigger. No automatic healing, disk writes or actor mutation.
signal saved(actor: Node2D, checkpoint: Dictionary)
const Native = preload("../../Core/Native/Runtime/InariCheckpoint.gd")
const Configuration = preload("CheckpointSettings.gd")
@export var settings: Configuration = preload("CheckpointSettings.tres")
## Assign a stable, unique host ID when persisting beyond this scene session.
@export var checkpoint_id := ""
@export_flags_2d_physics var actor_layers := 4
var mechanism: Area2D
var actor_ref: WeakRef
var eligible: Callable


func _ready() -> void:
	var record := prepare("Checkpoint")
	if Engine.is_editor_hint():
		queue_redraw()
		return
	record.size = [settings.trigger_size.x, settings.trigger_size.y]
	record.offset = [settings.trigger_offset.x, settings.trigger_offset.y]
	mechanism = Native.new()
	mechanism.accept_actor = _accept_actor
	add_child(mechanism)
	mechanism.configure(record)
	mechanism.collision_mask = actor_layers
	mechanism.activated = settings.initially_activated
	mechanism.saved.connect(_saved)


func bind_actor(actor: Node2D, can_save: Callable = Callable()) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_save


func is_activated() -> bool:
	return is_instance_valid(mechanism) and mechanism.activated


func _accept_actor(actor: Node2D) -> bool:
	return (
		actor_ref != null
		and actor_ref.get_ref() == actor
		and actor.can_process()
		and (not eligible.is_valid() or bool(eligible.call()))
	)


func _saved(_point: Area2D) -> void:
	# Snapshot world coordinates at save time. A moving checkpoint must not drag
	# the previously stored spawn; hosts may choose a different policy explicitly.
	var payload := {
		"id": checkpoint_id,
		"position": to_global(settings.spawn_offset),
		"facing": settings.facing,
		"direction": (global_transform.x * settings.facing).normalized()
	}
	saved.emit(actor_ref.get_ref(), payload)


func _draw() -> void:
	# The selected source renderer is disabled. This outline is editor-only.
	if Engine.is_editor_hint() and settings != null:
		draw_rect(
			Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size),
			Color(0.4, 0.9, 1, 0.5),
			false,
			1
		)
		draw_circle(settings.spawn_offset, 4, Color.CYAN, false, 1)
