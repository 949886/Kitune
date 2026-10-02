extends RefCounted
## PNG is an sRGB deliverable; Godot HDR readbacks contain linear radiance.


static func for_png(source: Image, linear: bool) -> Image:
	var result := source.duplicate() as Image
	if linear:
		# Convert before quantization: dark HDR values would otherwise collapse to zero.
		for y in result.get_height():
			for x in result.get_width():
				var pixel := result.get_pixel(x, y)
				result.set_pixel(x, y, pixel.linear_to_srgb())
	result.convert(Image.FORMAT_RGBA8)
	return result


static func save_png(viewport: Viewport, path: String) -> Error:
	return for_png(viewport.get_texture().get_image(), viewport.use_hdr_2d).save_png(path)
