@tool
extends "../../Core/DeviceHost.gd"
## A signal-controlled door; no player, combat manager or save singleton required.
## Logical state changes immediately; passability waits for the source animation.
signal state_changed(open: bool)
signal passability_changed(passable: bool)
signal attachments_invalidated(surfaces: Array[StaticBody2D])
const Native = preload("../../Core/Native/Runtime/InariMachineDoor.gd")
const Configuration = preload("DoorSettings.gd")
@export var settings: Configuration = preload("DoorSettings.tres")
@export_flags_2d_physics var solid_layers := 1
var mechanism: Node


func _ready() -> void:
	var record := prepare("MachineDoor")
	if Engine.is_editor_hint():
		return
	record.fields.isOpening = settings.initial_open
	record.fields.colliderTiming = settings.collider_release_fraction
	mechanism = Native.new()
	mechanism.collision_layers = solid_layers
	add_child(mechanism)
	mechanism.configure(record, self, null)
	# Initial state is queried, not emitted as a command during scene setup.
	mechanism.state_changed.connect(func(value: bool): state_changed.emit(value))
	mechanism.passability_changed.connect(func(value: bool): passability_changed.emit(value))
	mechanism.attachments_invalidated.connect(_invalidate_attachments)
	for body: StaticBody2D in mechanism.bodies:
		body.set_meta("device", self)


func toggle() -> void:
	mechanism.notify()


func open() -> void:
	if not is_open():
		toggle()


func close() -> void:
	if is_open():
		toggle()


func is_open() -> bool:
	return is_instance_valid(mechanism) and mechanism.is_open


func is_passable() -> bool:
	return is_instance_valid(mechanism) and mechanism.passable


func _invalidate_attachments(surfaces: Array[StaticBody2D]) -> void:
	# The host may detach/destroy projectiles stuck in these surfaces. A portable
	# door cannot assume the host's projectile class or ownership rules.
	attachments_invalidated.emit(surfaces)
