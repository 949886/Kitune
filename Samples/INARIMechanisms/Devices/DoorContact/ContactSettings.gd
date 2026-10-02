@tool
extends Resource
@export var trigger_size := Vector2(24, 383.42462158203125)
@export var trigger_offset := Vector2(0, -133.79232788085938)
## Trigger.once and DoorContactTrigger.isOnce have distinct persistence fields.
@export var once := false
@export var door_once := true
@export var initially_active := true
@export var restored_activated := false
