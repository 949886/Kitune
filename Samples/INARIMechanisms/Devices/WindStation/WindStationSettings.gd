@tool
extends Resource
## Authored trigger defaults live in the adjacent exported .tres.
@export var trigger_size := Vector2.ONE
@export var trigger_offset := Vector2.ZERO
@export_range(0, 60, 0.01, "or_greater") var cooldown_seconds := 0.0
@export var stamina_amount := 0.0
@export var story_heal_amount := 0
@export var stamina_already_granted := false
