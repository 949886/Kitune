extends BackBufferCopy
## URP copies the camera through Ground2 before drawing Enemy and higher layers.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
var settings: Dictionary = Assets.read_json(Assets.ROOT + "shockwave.json")


func configure(sorting: Callable) -> void:
	assert(settings.downsampling == 0)
	copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	z_as_relative = false
	z_index = sorting.call(settings.capture_order_before)
	visible = settings.capture_enabled
