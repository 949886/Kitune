@tool
extends "../../Core/DeviceTiledSprite.gd"
## Unity SpriteRenderer.m_Size is measured in source units. Rebuild the
## continuous tiled geometry, including its border and pivot, as rods extend.
func set_source_height(value: float) -> void:
	var pixels := maxf(0.0, value * 16.0)
	if is_equal_approx(float(data.size[1]), pixels):
		return
	data.size[1] = pixels
	_layout(sprite_library[data.sprite])
