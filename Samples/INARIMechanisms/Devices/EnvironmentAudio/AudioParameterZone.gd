@tool
extends "../../Core/SourceTriggerArea.gd"
## Source parameter overrides execute even when loading gates base callbacks.
signal parameters_requested(family: String, guid: String, values: Dictionary)


func _init() -> void:
	settings = preload("Presets/level15_11051.tres")


func bind_audio(mixer: Node) -> void:
	parameters_requested.connect(mixer.apply_zone)


func _apply() -> void:
	super._apply()
	parameters_requested.emit(settings.family, settings.event_guid, settings.parameters.duplicate(true))
