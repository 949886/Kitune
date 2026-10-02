@tool
extends "DeviceSprite.gd"
## Source continuous nine-slice/tiling, sharing the original flat renderer's
## clipping rules. Geometry is in texture pixels before DeviceSprite's PPU scale.
const Slicing = preload("Native/Runtime/OriginalSpriteSlicing.gd")
var tiled_texture: Texture2D
var quads: Array[Rect2] = []
var destination: Rect2


func configure(record: Dictionary, info: Dictionary, folder: String) -> void:
	super.configure(record, info, folder)
	tiled_texture = texture
	texture = null
	_layout(info)


func set_animation_sprite(key: Variant) -> void:
	if key == null:
		tiled_texture = null
	else:
		var info: Dictionary = sprite_library[key]
		tiled_texture = load(asset_folder + info.path)
		_layout(info)
	queue_redraw()


func _layout(info: Dictionary) -> void:
	var size := Vector2(data.size[0], data.size[1]) * float(info.ppu) / 16.0
	destination = Rect2(-size / 2.0, size)
	quads.clear()
	var slicing: Dictionary = info.get("slicing", {})
	if not slicing.is_empty():
		destination.position = -Vector2(slicing.pivot[0], slicing.pivot[1]) * size
		quads = Slicing.build(slicing, destination, 1.0, int(data.mode) == 2)
	queue_redraw()


func _draw() -> void:
	if tiled_texture == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1 if flip_h else 1, -1 if flip_v else 1))
	if not quads.is_empty():
		for index in range(0, quads.size(), 2):
			draw_texture_rect_region(tiled_texture, quads[index], quads[index + 1])
	elif int(data.mode) != 2:
		draw_texture_rect(tiled_texture, destination, false)
	else:
		var tile_size := tiled_texture.get_size()
		for y in ceili(destination.size.y / tile_size.y):
			for x in ceili(destination.size.x / tile_size.x):
				var start := Vector2(x, y) * tile_size
				var part := (destination.size - start).min(tile_size)
				draw_texture_rect_region(
					tiled_texture,
					Rect2(destination.position + start, part),
					Rect2(Vector2.ZERO, part)
				)
