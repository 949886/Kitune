@tool
extends Resource
## Source defaults are exported into the adjacent .tres. The host owns storage
## and maps the authored spawn origin to its own character's origin convention.
@export var trigger_size := Vector2.ONE
@export var trigger_offset := Vector2.ZERO
@export var spawn_offset := Vector2.ZERO
@export_enum("Left:-1", "Right:1") var facing := 1
@export var initially_activated := false
