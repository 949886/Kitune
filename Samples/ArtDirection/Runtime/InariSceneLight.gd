@tool
extends Marker2D
## Native light settings remain inspectable; position/color/energy are editable
## scene properties. The original layer-light shader consumes the resulting record.

@export var definition: Dictionary
@export var light_color := Color.WHITE
@export var energy := 1.0
@export var radius := 16.0
@export var depth := 0.0


func source_data() -> Dictionary:
	var result := definition.duplicate(true)
	var pose := global_transform
	result.transform = [pose.x.x, pose.x.y, pose.y.x, pose.y.y, pose.origin.x, pose.origin.y]
	result.spatial.transform = result.transform
	result.spatial.depth = depth
	result.color = [light_color.r, light_color.g, light_color.b, light_color.a]
	result.energy = energy
	result.radius = radius
	return result
