@tool
extends Marker2D
## Enemy placement is scene-authored; the runtime actor reads its native behavior.

@export var definition: Resource


func source_data() -> Dictionary:
	var result: Dictionary = definition.data.duplicate(true)
	var offset := global_position - Vector2(result.position[0], result.position[1])
	result.position = [global_position.x, global_position.y]
	result.gfx_position[0] += offset.x
	result.gfx_position[1] += offset.y
	return result
