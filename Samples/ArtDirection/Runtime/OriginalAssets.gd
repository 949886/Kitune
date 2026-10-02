@tool
extends RefCounted
## Shared, lossless original INARI sprite atlas reader.

const ROOT := "res://Samples/ArtDirection/Original/INARI/"
static var sprites: Dictionary = {}
static var textures: Dictionary = {}
static var materials: Dictionary = {}


static func material_info(key: String) -> Dictionary:
	if materials.is_empty():
		materials = read_json(ROOT + "materials.json")
	return materials.get(key, {})


static func read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func sprite_info(key: String) -> Dictionary:
	if sprites.is_empty():
		sprites = read_json(ROOT + "sprites.json")
	return sprites[key]


static func texture(key: String) -> AtlasTexture:
	if not textures.has(key):
		var info := sprite_info(key)
		var result := AtlasTexture.new()
		var path: String = info.path if info.has("path") else "atlas_%d.png" % info.atlas
		result.atlas = load(ROOT + path)
		result.region = rect(info.region)
		result.filter_clip = true
		textures[key] = result
	return textures[key]


static func vec(values: Array) -> Vector2:
	return Vector2(values[0], values[1])


static func rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])


static func color(values: Array) -> Color:
	return Color(values[0], values[1], values[2], values[3])


static func matrix(values: Array) -> Transform2D:
	return Transform2D(
		Vector2(values[0], values[1]), Vector2(values[2], values[3]), Vector2(values[4], values[5])
	)
