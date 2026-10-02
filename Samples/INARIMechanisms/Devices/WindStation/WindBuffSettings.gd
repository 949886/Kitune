extends Resource
## Index zero is the inactive level. Speeds are pixels/second, durations seconds.
## Keep profiles independent when customizing individual character instances.
@export var extra_speed_pixels := PackedFloat32Array()
@export var durations := PackedFloat32Array()


func is_valid() -> bool:
	if extra_speed_pixels.size() < 2 or extra_speed_pixels.size() != durations.size():
		return false
	for index in extra_speed_pixels.size():
		if extra_speed_pixels[index] < 0 or (index > 0 and durations[index] <= 0):
			return false
	return true
