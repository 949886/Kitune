@tool
extends Resource
@export var trigger_transform := Transform2D.IDENTITY
@export var trigger_size := Vector2.ONE
@export var trigger_offset := Vector2.ZERO
@export var collider_enabled := true
@export var initially_active := true
@export var once := false
@export var on_field := false
@export_range(0, 30, 0.01, "or_greater") var delay_seconds := 1.25
