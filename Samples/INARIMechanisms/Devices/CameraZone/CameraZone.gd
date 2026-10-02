@tool
extends Area2D
## Physical region shared with the original demo. Bind explicitly to the camera
## coordinator; no player type, scene lookup, InputMap or Autoload is required.
const Configuration = preload("ZoneSettings.gd")
@export var settings: Configuration = preload("Presets/level15_11037.tres")
@export_flags_2d_physics var actor_layers := 4
var source: Dictionary
var manager: Node
var inside := false
var consumed := false
var entries := 0
var exits := 0
var active := true
var shape: CollisionShape2D


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if source.is_empty():
		configure(settings.record(), null)
		set_active(settings.initially_active)


## Native adapter supplies the original serialized record and placement.
func configure(record: Dictionary, owner_manager: Node) -> void:
	source = record
	collision_layer = 0
	collision_mask = actor_layers
	monitorable = false
	var box := RectangleShape2D.new()
	box.size = Vector2(record.size[0], record.size[1])
	shape = CollisionShape2D.new()
	shape.shape = box
	shape.position = Vector2(record.offset[0], record.offset[1])
	add_child(shape)
	body_entered.connect(_enter)
	body_exited.connect(_exit)
	bind_controller(owner_manager)


func bind_controller(coordinator: Node) -> void:
	if manager == coordinator: return
	if is_instance_valid(manager): manager.remove_zone(self)
	manager = coordinator
	inside = false
	if is_instance_valid(manager) and not self in manager.zones: manager.zones.append(self)


func set_active(value: bool) -> void:
	active = value
	shape.set_deferred("disabled", not value)
	# Re-enabling the collider is explicit host control; source isOnce has
	# already been cleared on consumption, so subsequent exits are repeatable.
	if value: consumed = false


func _enter(body: Node) -> void:
	if not active or not is_instance_valid(manager) or not manager.accept_actor(body) or consumed or inside:
		return
	inside = true
	entries += 1
	manager.enter(self)


func _exit(body: Node) -> void:
	if not is_instance_valid(manager) or body != manager.player or not inside:
		return
	if manager.ignore_exit.is_valid() and bool(manager.ignore_exit.call(body)):
		return
	inside = false
	exits += 1
	manager.leave(self)
	if source.fields.isOnce:
		source.fields.isOnce = false
		consumed = true
		active = false
		shape.set_deferred("disabled", true)


func _exit_tree() -> void:
	if is_instance_valid(manager): manager.remove_zone(self)


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size), Color(0.3, 0.8, 0.9, 0.2))
