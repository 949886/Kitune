@tool
extends "../../Core/SourceTriggerArea.gd"
## The source overrides still write on loading-time entry/exit. There is no
## Stay callback and no automatic restoration of a previous region's value.
signal distance_requested(units: float)


func _init() -> void:
	settings = preload("Presets/level12_9145.tres")


func bind_range(controller: Node) -> void:
	distance_requested.connect(controller.set_additive_distance)


func _apply() -> void:
	super._apply()
	distance_requested.emit(settings.additive_distance)


func _exit() -> void:
	super._exit()
	distance_requested.emit(0.0)
