@tool
extends "../../Core/DeviceHost.gd"
signal activated
signal switched(enabled: bool)
const Native = preload("../../Core/Native/Runtime/InariLever.gd")
const Configuration = preload("LeverSettings.gd")
@export var settings: Configuration = preload("LeverSettings.tres")
@export_flags_2d_physics var hit_layers := 2
var mechanism: StaticBody2D


func _ready() -> void:
	var record := prepare("Lever")
	if Engine.is_editor_hint():
		return
	record.fields.InteractableType = settings.interaction_mask
	record.fields.isOnce = settings.single_use
	record.fields.IsInvincible = settings.invincible
	mechanism = Native.new()
	mechanism.configure(record, self, {})
	mechanism.collision_layer = hit_layers
	mechanism.set_meta("device", self)
	add_child(mechanism)
	mechanism.activated.connect(_activated)


func receive_hit(interaction: int, actor: Node = null, direction := 1.0) -> bool:
	return mechanism.receive_study_hit(
		{"interaction": interaction, "source_actor": actor}, direction
	)


func _activated() -> void:
	switched.emit(mechanism.switched_on)
	activated.emit()
