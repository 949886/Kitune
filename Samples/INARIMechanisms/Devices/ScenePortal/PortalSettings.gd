@tool
extends Resource
## All shipped presets are exported from their actual trigger and scene GUID.
## Input direction is world input, independent of the area's root rotation.
@export var trigger_size := Vector2.ONE
@export var trigger_offset := Vector2.ZERO
@export var destination := ""
@export var once := true
@export var maintain_input := false
@export var input_direction := Vector2.ZERO
@export var initially_active := true
