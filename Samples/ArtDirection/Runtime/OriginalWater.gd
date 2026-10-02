extends RefCounted
## Shared source water settings and a lossless texture retaining every native mip.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const WaterShader = preload("res://Samples/ArtDirection/Shaders/OriginalWater.gdshader")

static var settings: Dictionary = {}
static var normal: ImageTexture


static func source_settings() -> Dictionary:
	if settings.is_empty():
		settings = Assets.read_json(Assets.ROOT + "water.json")
	return settings


static func normal_texture() -> ImageTexture:
	if normal == null:
		var source: Dictionary = source_settings().normal
		var bytes := PackedByteArray()
		for mip: Dictionary in source.mips:
			# The checked-in import settings preserve RGBA bytes and disable mip
			# regeneration/channel conversion. Resources also work in a PCK export.
			var texture: Texture2D = load(Assets.ROOT + mip.path)
			var image := texture.get_image()
			image.convert(Image.FORMAT_RGBA8)
			bytes.append_array(image.get_data())
		var base: Dictionary = source.mips[0]
		var image := Image.create_from_data(
			base.width, base.height, true, Image.FORMAT_RGBA8, bytes
		)
		normal = ImageTexture.create_from_image(image)
	return normal


static func configure(material: ShaderMaterial, hdr: bool) -> void:
	var source: Dictionary = source_settings().material
	material.set_shader_parameter("water_normal", normal_texture())
	material.set_shader_parameter("water_speed", source._Speed)
	material.set_shader_parameter("water_strength", source._Strength)
	material.set_shader_parameter("water_tiling", source._Tilling)
	material.set_shader_parameter("water_surface_speed", source._SurfaceSpeed)
	material.set_shader_parameter("linear_framebuffer", hdr)
