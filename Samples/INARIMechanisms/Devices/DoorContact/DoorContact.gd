@tool
extends Node2D
## Contact emits the source observer notification (usually Door.toggle), then
## requests removal only of the host's projectiles outside the battle room.
signal contacted(actor: Node2D)
signal outside_projectiles_cleanup_requested(actor: Node2D)
signal save_requested(record: Dictionary)
const Area = preload("../../Core/Native/Runtime/InariScenePortal.gd")
const Configuration = preload("ContactSettings.gd")
@export var settings: Configuration = preload("ContactSettings.tres")
@export_flags_2d_physics var actor_layers := 4
var area: Area2D
var actor_ref: WeakRef
var eligible: Callable
var loading: Callable
var activated := false


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	activated = settings.restored_activated
	area = Area.new()
	area.accept_actor = _accept
	area.is_loading = func(): return loading.is_valid() and bool(loading.call())
	add_child(area)
	area.configure({"fields": {"once": settings.once}, "trigger": {
		"transform": [1, 0, 0, 1, 0, 0],
		"size": [settings.trigger_size.x, settings.trigger_size.y],
		"offset": [settings.trigger_offset.x, settings.trigger_offset.y]}}, null)
	area.collision_mask = actor_layers
	area.set_active(settings.initially_active and not activated)
	area.requested.connect(_contact)


func bind_actor(actor: Node2D, can_enter: Callable = Callable(), is_loading: Callable = Callable()) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_enter
	loading = is_loading


func _accept(actor: Node2D) -> bool:
	return actor_ref != null and actor_ref.get_ref() == actor and actor.can_process() and (
		(actor.collision_layer & actor_layers) != 0) and (not eligible.is_valid() or bool(eligible.call()))


func _contact(_record: Dictionary) -> void:
	var actor: Node2D = actor_ref.get_ref()
	# Commit consumption before calling a reentrant host. Door collision edits
	# should be deferred by the subscriber when responding inside physics.
	if settings.door_once:
		activated = true
		area.set_active(false)
	contacted.emit(actor)
	if settings.door_once:
		save_requested.emit({"isActivated": true})
	outside_projectiles_cleanup_requested.emit(actor)
	area.finish_request()


func activate() -> void:
	area.set_active(true)
	save_requested.emit({"isActive": true})


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size), Color(0.9, 0.5, 0.2, 0.25))
