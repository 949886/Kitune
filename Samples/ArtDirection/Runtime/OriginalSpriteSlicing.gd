extends RefCounted
## Unity Continuous nine-slice layout, shared by flat and perspective renderers.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
static var definitions: Dictionary = {}


static func definition(key: String) -> Dictionary:
	if definitions.is_empty():
		definitions = Assets.read_json(Assets.ROOT + "sprite_slicing.json").sprites
	return definitions.get(key, {})


static func build(info: Dictionary, destination: Rect2, units: float, tiled: bool) -> Array[Rect2]:
	var border: Array = info.border
	var horizontal := _axis(destination.size.x, info.size[0], border[0], border[2], units, tiled)
	# Unity starts tiles at bottom-left. After changing to Godot's Y-down axis,
	# an incomplete vertical tile belongs at the top of the repeated region.
	var vertical := _axis(destination.size.y, info.size[1], border[3], border[1], units, tiled)
	for index in vertical.size():
		var span := vertical[index]
		span.x = destination.size.y - span.x - span.y
		span.z = float(info.size[1]) - span.z - span.w
		vertical[index] = span
	var trim := Assets.rect(info.trim)
	var quads: Array[Rect2] = []
	for y: Vector4 in vertical:
		for x: Vector4 in horizontal:
			var region := Rect2(x.z, y.z, x.w, y.w)
			var clipped := region.intersection(trim)
			if not clipped.has_area():
				continue
			# AtlasTexture contains only the trimmed source. Clip geometry and UVs
			# together so transparent margins do not shift borders or the pivot.
			var scale := Vector2(x.y, y.y) / region.size
			var position := Vector2(x.x, y.x) + (clipped.position - region.position) * scale
			quads.append(Rect2(destination.position + position, clipped.size * scale))
			quads.append(Rect2(clipped.position - trim.position, clipped.size))
	return quads


static func _axis(
	length: float, pixels: float, start: float, end: float, units: float, tiled: bool
) -> Array[Vector4]:
	var spans: Array[Vector4] = []
	var border_scale := minf(1.0, length / ((start + end) * units)) if start + end > 0.0 else 1.0
	var first := start * units * border_scale
	var last := end * units * border_scale
	if first > 0.0:
		spans.append(Vector4(0.0, first, 0.0, start))
	var middle := maxf(0.0, length - first - last)
	var source_middle := pixels - start - end
	if middle > 0.0 and source_middle > 0.0:
		if tiled:
			var step := source_middle * units
			for index in ceili(middle / step):
				var size := minf(step, middle - index * step)
				spans.append(Vector4(first + index * step, size, start, size / units))
		else:
			spans.append(Vector4(first, middle, start, source_middle))
	if last > 0.0:
		spans.append(Vector4(length - last, last, pixels - end, end))
	return spans
