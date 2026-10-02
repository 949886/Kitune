extends Resource
## Shared geometry and persistence fields from the source Trigger component.
@export var trigger_size := Vector2(160, 160)
@export var trigger_offset := Vector2.ZERO
@export var source_transform := Transform2D.IDENTITY
@export var initially_active := true
@export var once := false
@export var source_layer_bits := 64
@export var persistence_id := ""
