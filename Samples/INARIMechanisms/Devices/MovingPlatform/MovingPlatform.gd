@tool
extends "../../Core/DeviceHost.gd"
## Native timing/easing with an explicit, optional passenger adapter.
signal started
signal arrived
signal passenger_crushed(actor: CharacterBody2D)
const Native = preload("../../Core/Native/Runtime/InariMovingPlatform.gd")
const Configuration = preload("PlatformSettings.gd")
@export var settings: Configuration = preload("PlatformSettings.tres")
@export_flags_2d_physics var solid_layers := 1
@export_node_path("CharacterBody2D") var passenger_path: NodePath
@export_node_path("CollisionShape2D") var passenger_shape_path: NodePath
var mechanism: StaticBody2D


func _get_configuration_warnings() -> PackedStringArray:
	if passenger_path.is_empty() != passenger_shape_path.is_empty():
		return ["Set both passenger paths, or leave both empty and call bind_passenger()."]
	return []


func _ready() -> void:
	var record := prepare("MovingPlatform")
	if Engine.is_editor_hint():
		return
	assert(settings.travel_offset != Vector2.ZERO and settings.speed_pixels_per_second > 0.0)
	record.waypoints = [[0.0, 0.0], [settings.travel_offset.x, settings.travel_offset.y]]
	record.fields.Speed = settings.speed_pixels_per_second / 16.0
	record.fields.WaitTime = settings.wait_seconds
	record.fields.EaseAmount = settings.ease_amount
	record.fields.Cyclic = settings.cyclic
	record.fields.IsStopped = settings.stop_at_waypoints
	mechanism = Native.new()
	mechanism.use_passenger_adapter = true
	mechanism.configure(record, null, visual_instances)
	mechanism.collision_layer = solid_layers
	add_child(mechanism)
	mechanism.started.connect(started.emit)
	mechanism.arrived.connect(arrived.emit)
	mechanism.passenger_crushed.connect(passenger_crushed.emit)
	if not passenger_path.is_empty():
		bind_passenger(get_node(passenger_path), get_node(passenger_shape_path))


func bind_passenger(actor: CharacterBody2D, shape: CollisionShape2D) -> void:
	assert(actor.is_ancestor_of(shape), "Passenger shape must belong to the bound actor")
	mechanism.player = actor
	mechanism.passenger_shape = shape


func set_passenger_grip(climbing: bool, hanging: bool) -> void:
	mechanism.passenger_climbing = climbing
	mechanism.passenger_hanging = hanging


func unbind_passenger() -> void:
	mechanism.player = null
	mechanism.passenger_shape = null
	set_passenger_grip(false, false)


func activate() -> void:
	mechanism.activate()


func set_motion_scale(value: float) -> void:
	mechanism.on_source_time_scale(maxf(0.0, value))
