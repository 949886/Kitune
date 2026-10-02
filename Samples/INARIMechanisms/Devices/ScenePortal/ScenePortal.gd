@tool
extends Node2D
## Invisible source trigger: the host owns loading, actor controls and storage.
## Signals carry snapshots; changing settings later cannot mutate a request.
signal transition_requested(actor: Node2D, request: Dictionary)
signal active_changed(active: bool)
const Native = preload("../../Core/Native/Runtime/InariScenePortal.gd")
const Configuration = preload("PortalSettings.gd")
@export var settings: Configuration = preload("Presets/level14.tres")
@export_flags_2d_physics var actor_layers := 4
@export var portal_id := ""
var mechanism: Area2D
var actor_ref: WeakRef
var eligible: Callable
var loading: Callable


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	assert(settings.trigger_size.x > 0 and settings.trigger_size.y > 0)
	mechanism = Native.new()
	mechanism.accept_actor = _accept_actor
	mechanism.is_loading = _is_loading
	add_child(mechanism)
	mechanism.configure(
		{
			"fields": {"once": settings.once},
			"trigger":
			{
				"transform": [1, 0, 0, 1, 0, 0],
				"size": [settings.trigger_size.x, settings.trigger_size.y],
				"offset": [settings.trigger_offset.x, settings.trigger_offset.y]
			}
		},
		null
	)
	mechanism.collision_mask = actor_layers
	mechanism.set_active(settings.initially_active)
	mechanism.requested.connect(_requested)


## Binding is allowed before add_child, so initial overlap is not missed.
## is_scene_loading must describe the shared host transaction, not just this exit.
func bind_actor(
	actor: Node2D, can_transition: Callable = Callable(), is_scene_loading: Callable = Callable()
) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	eligible = can_transition
	loading = is_scene_loading


func unbind_actor() -> void:
	actor_ref = null
	eligible = Callable()
	loading = Callable()


func _accept_actor(actor: Node2D) -> bool:
	return (
		actor_ref != null
		and actor_ref.get_ref() == actor
		and actor.can_process()
		and (actor.collision_layer & actor_layers) != 0
		and (not eligible.is_valid() or bool(eligible.call()))
	)


func _is_loading() -> bool:
	return loading.is_valid() and bool(loading.call())


func _requested(_record: Dictionary) -> void:
	# Native state is committed before any host callback can re-enter this API.
	var actor: Node2D = actor_ref.get_ref()
	var preserve_input := settings.maintain_input and settings.input_direction == Vector2.ZERO
	var injected := Vector2.ZERO
	if settings.maintain_input and not preserve_input:
		# PlayerInputController.SetMaintainInput uses Unity Mathf.Sign per axis,
		# including Sign(0) = +1. Convert the resulting Unity Y to Godot Y.
		injected = Vector2(
			1 if settings.input_direction.x >= 0 else -1,
			-1 if settings.input_direction.y <= 0 else 1
		)
	var payload := {
		"id": portal_id,
		"destination": settings.destination,
		"maintain_input": settings.maintain_input,
		"input_direction": settings.input_direction,
		"preserve_last_input": preserve_input,
		"injected_input": injected,
		"grant_invincibility": settings.maintain_input,
		"reset_dash": settings.maintain_input
	}
	if mechanism.once:
		active_changed.emit(false)
	if is_instance_valid(actor):
		transition_requested.emit(actor, payload)


func is_active() -> bool:
	return is_instance_valid(mechanism) and mechanism.active


func is_pending() -> bool:
	return is_instance_valid(mechanism) and mechanism.pending


func finish_request() -> void:
	mechanism.finish_request()


func set_active(value: bool) -> void:
	var changed := is_active() != value
	mechanism.set_active(value)
	if changed:
		active_changed.emit(value)


func _draw() -> void:
	if Engine.is_editor_hint() and settings != null:
		draw_rect(
			Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size),
			Color(0.45, 0.9, 1, 0.7),
			false,
			2
		)
