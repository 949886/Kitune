@tool
extends Area2D
## Shared source Trigger lifecycle. Derived classes apply their effect after
## the base callbacks, including when loading suppresses only base events.
signal entered
signal exited
signal loaded(active: bool)
signal save_requested(record: Dictionary)
@export var settings: Resource = preload("TriggerSettings.gd").new()
@export_flags_2d_physics var actor_layers := 4
var actor_ref: WeakRef
var loading: Callable
var active := true
var data_changed := false
var calls := 0
var shape: CollisionShape2D


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	collision_layer = 0
	collision_mask = actor_layers if settings.source_layer_bits != 0 else 0
	monitorable = false
	shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = settings.trigger_size
	shape.shape = box
	shape.position = settings.trigger_offset
	add_child(shape)
	active = settings.initially_active
	shape.disabled = not active
	body_entered.connect(_physical_enter)
	body_exited.connect(_physical_exit)
	_initial_overlap()


func bind_actor(actor: Node2D, is_loading: Callable = Callable()) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	loading = is_loading


func _accept(actor: Node2D) -> bool:
	return actor_ref != null and actor_ref.get_ref() == actor and (actor.collision_layer & collision_mask) != 0


func _initial_overlap() -> void:
	await get_tree().physics_frame
	call_deferred("_check_initial_overlap")


func _check_initial_overlap() -> void:
	if not is_inside_tree() or not active or shape.disabled: return
	# Source OnEnable explicitly checks initial overlaps in addition to Unity
	# Enter callbacks. A derived effect must retain its own repeated-entry policy.
	for actor: Node2D in get_overlapping_bodies():
		if _accept(actor): _apply()


func _physical_enter(actor: Node2D) -> void:
	if _accept(actor): _apply()


func _physical_exit(actor: Node2D) -> void:
	if _accept(actor): _exit()


func _exit() -> void:
	if not _loading(): exited.emit()


func _loading() -> bool:
	return loading.is_valid() and bool(loading.call())


## Explicit source InteractiveShuriken entry bypasses the trigger layer and
## disabled collider; the same override is called even after once consumption.
func interactive_shuriken() -> void:
	_apply()


func _apply() -> void:
	if not _loading():
		if settings.once:
			active = false
			data_changed = true
			shape.set_deferred("disabled", true)
		entered.emit()
	calls += 1


func activate() -> void:
	active = true
	data_changed = true
	shape.set_deferred("disabled", false)
	save_requested.emit(save_data())


func load_data(record: Dictionary) -> void:
	# Source TryGetValue accepts only bool; malformed host data falls back to
	# the collider's current enabled state instead of coercing strings/numbers.
	var saved = record.get(settings.persistence_id + "_isActive")
	active = saved if saved is bool else not shape.disabled
	shape.set_deferred("disabled", not active)
	loaded.emit(active)


func save_data():
	if not data_changed: return null
	data_changed = false
	return {settings.persistence_id + "_isActive": active}


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size), Color(0.35, 0.7, 0.95, 0.2))
