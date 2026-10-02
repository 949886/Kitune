extends SceneTree
## Run only inside the isolated resource pack created by WaterResourceProbe.

const Water = preload("res://Samples/ArtDirection/Runtime/OriginalWater.gd")


func _initialize() -> void:
	var settings := Water.source_settings()
	for mip: Dictionary in settings.normal.mips:
		var path := "res://Samples/ArtDirection/Original/INARI/" + str(mip.path)
		assert(not FileAccess.file_exists(path), "Pack must exclude original PNG files")
		assert(ResourceLoader.exists(path), "Imported resource remap is missing")
	var image := Water.normal_texture().get_image()
	assert(image.get_mipmap_count() == 9)
	var bytes := image.get_data()
	for level in settings.normal.mips.size():
		var mip: Dictionary = settings.normal.mips[level]
		var offset := image.get_mipmap_offset(level)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes.slice(offset, offset + int(mip.width * mip.height * 4)))
		assert(hash.finish().hex_encode() == mip.rgba_sha256, "Pack changed source pixels")
	print("WATER_PACKED_PASS")
	quit()
