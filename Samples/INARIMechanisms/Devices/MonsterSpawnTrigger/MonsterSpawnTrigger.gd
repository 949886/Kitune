@tool
extends Node2D
## Invisible, relocatable trigger. Connect spawn_requested to a ready host's
## BattleEncounter.start_spawn; storage and actor identity belong to the host.
signal entered(actor: Node2D)
signal exited(actor: Node2D)
signal spawn_requested
signal activation_changed(activated: bool)
signal save_requested(record: Dictionary)
const Native = preload("../../Core/Native/Runtime/InariMonsterSpawnTrigger.gd")
const Configuration = preload("SpawnTriggerSettings.gd")
@export var settings: Configuration = Configuration.new()
@export_flags_2d_physics var actor_layers := 4
@export var restored_activated := false
var mechanism: Area2D
var actor_ref: WeakRef
var eligible: Callable
var loading: Callable


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	mechanism = Native.new()
	mechanism.accept_actor = _accept
	mechanism.is_loading = func(): return loading.is_valid() and bool(loading.call())
	add_child(mechanism)
	var pose := settings.trigger_transform
	mechanism.configure({"active": settings.initially_active,
		"fields": {"once": settings.once, "spawnTerm": settings.delay_seconds},
		"trigger": {"transform": [pose.x.x, pose.x.y, pose.y.x, pose.y.y, pose.origin.x, pose.origin.y],
			"size": [settings.trigger_size.x, settings.trigger_size.y],
			"offset": [settings.trigger_offset.x, settings.trigger_offset.y],
			"enabled": settings.collider_enabled}}, null, settings.on_field)
	mechanism.collision_mask = actor_layers
	mechanism.restore({"isActivated": restored_activated})
	mechanism.entered.connect(func(actor): entered.emit(actor))
	mechanism.exited.connect(func(actor): exited.emit(actor))
	mechanism.spawn_requested.connect(func(): spawn_requested.emit())
	mechanism.activation_changed.connect(func(value): activation_changed.emit(value))
	mechanism.save_requested.connect(func(record): save_requested.emit(record))


func bind_actor(actor: Node2D, can_enter: Callable = Callable(), is_scene_loading: Callable = Callable()) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_enter
	loading = is_scene_loading


func _accept(actor: Node2D) -> bool:
	return actor_ref != null and actor_ref.get_ref() == actor and actor.can_process() and (
		(actor.collision_layer & actor_layers) != 0) and (not eligible.is_valid() or bool(eligible.call()))


func set_active(value: bool) -> void:
	mechanism.set_object_active(value)


func activate_trigger() -> void:
	mechanism.activate_trigger()


func snapshot() -> Dictionary:
	return mechanism.snapshot()


func restore(record: Dictionary) -> void:
	mechanism.restore(record)


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_set_transform_matrix(settings.trigger_transform)
		draw_rect(Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size), Color(0.9, 0.7, 0.2, 0.25))
