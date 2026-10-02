extends Resource
## Geometry uses Godot pixels; camera offset/distance retain source world units.
## source_transform is optional placement evidence, never applied implicitly.
enum Kind { DISTANCE, FIXED }
@export var kind := Kind.DISTANCE
@export var trigger_size := Vector2(160, 160)
@export var trigger_offset := Vector2.ZERO
@export var initially_active := true
@export var once := false
@export var tracked_offset := Vector3.ZERO
@export var damping := 5.0
@export var blend := Vector2.ONE
@export var distance := 0.0
@export var source_transform := Transform2D.IDENTITY


func record() -> Dictionary:
	return {"kind": "CameraFixTargetTrigger" if kind == Kind.FIXED else "CameraDistanceTrigger",
		"size": [trigger_size.x, trigger_size.y], "offset": [trigger_offset.x, trigger_offset.y],
		"fields": {"isOnce": once, "offset": {"x": tracked_offset.x, "y": tracked_offset.y, "z": tracked_offset.z},
			"damping": damping, "xDamp": blend.x, "yDamp": blend.y, "distance": distance}}
