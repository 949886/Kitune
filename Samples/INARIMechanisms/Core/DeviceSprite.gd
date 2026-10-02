@tool
extends Sprite2D
## Minimal native sprite adapter shared by portable devices and source tracks.
const Settings = preload("Native/Runtime/OriginalMaterial.gd")
const Glow = preload("Native/Shaders/OriginalGlow.gdshader")
var animation_offset := Vector2.ZERO
var initial_rotation := 0.0
var data: Dictionary
var sprite_library: Dictionary = {}
var asset_folder := ""


func configure(record: Dictionary, info: Dictionary, folder: String) -> void:
	data = record
	asset_folder = folder
	texture = load(folder + info.path)
	centered = false
	offset = Vector2(info.offset[0], info.offset[1])
	scale = Vector2.ONE * 16.0 / float(info.ppu)
	var values: Array = record.transform
	transform = (
		Transform2D(
			Vector2(values[0], values[1]),
			Vector2(values[2], values[3]),
			Vector2(values[4], values[5])
		)
		* transform
	)
	initial_rotation = rotation
	modulate = Color(record.color[0], record.color[1], record.color[2], record.color[3])
	flip_h = record.flip[0]
	flip_v = record.flip[1]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = record.get("visible", true)
	if record.material.is_empty():
		return
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Glow
	Settings.configure(shader_material, record.material, get_viewport().use_hdr_2d)
	material = shader_material


func set_animation_sprite(key: Variant) -> void:
	if key == null:
		texture = null
		return
	var info: Dictionary = sprite_library[key]
	texture = load(asset_folder + info.path)
	offset = Vector2(info.offset[0], info.offset[1])


func set_animation_offset(value: Vector2) -> void:
	# Apply only the track's change so simultaneous platform travel survives.
	# Both offsets are in the portable host's local space, including when its
	# root is rotated/scaled. Resetting to the exported origin would pin a door
	# leaf to the departure station while the rest of the cabin moves away.
	position += value - animation_offset
	animation_offset = value


func set_animation_rotation(value: float) -> void:
	rotation = initial_rotation + value


func set_animation_visibility(value: bool) -> void:
	visible = value
