extends RefCounted
## Project native sprite triangles, retaining perspective UVs and camera clipping.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var spatial: Dictionary
var projection: Node
var triangles: Array[PackedVector4Array] = []
var texture: Texture2D
var sprite_key: Variant = null
var homography := Basis.IDENTITY
var inverse_weight := Vector3(0, 0, 1)


func configure(source: Dictionary, camera_projection: Node) -> void:
	spatial = source
	projection = camera_projection
	assert(spatial.has("depth_gradient"), "Reimport native tilted-plane depth gradients")


func draw(visual: Node2D) -> void:
	if visual.current_sprite != sprite_key:
		_build_triangles(visual)
	if triangles.is_empty() or not _update_projection(visual):
		return

	# Each tilted renderer owns its material; its projective row cannot be shared
	# with another sprite or with the independently positioned water camera.
	visual.material.set_shader_parameter("perspective_weight_row", inverse_weight)
	var local_from_world := visual.transform.affine_inverse()
	for triangle: PackedVector4Array in triangles:
		var clipped := _clip(triangle, projection.near_clip, true)
		clipped = _clip(clipped, projection.far_clip, false)
		if clipped.size() < 3:
			continue
		var points := PackedVector2Array()
		var uv := PackedVector2Array()
		for vertex: Vector4 in clipped:
			var point := homography * Vector3(vertex.x, vertex.y, 1.0)
			points.append(local_from_world * (Vector2(point.x, point.y) / point.z))
			uv.append(Vector2(vertex.z, vertex.w))
		# Camera-plane clipping leaves a convex polygon. Fan triangles avoid a
		# screen-space tessellator and preserve the original UV at every cut edge.
		for index in range(1, points.size() - 1):
			visual.draw_primitive(
				PackedVector2Array([points[0], points[index], points[index + 1]]),
				PackedColorArray([Color.WHITE]),
				PackedVector2Array([uv[0], uv[index], uv[index + 1]]),
				texture
			)


func _update_projection(visual: Node2D) -> bool:
	var world := Assets.matrix(spatial.transform)
	var flips := Vector2(-1 if visual.data.flip[0] else 1, -1 if visual.data.flip[1] else 1)
	world.x *= flips.x
	world.y *= flips.y
	var gradient := Assets.vec(spatial.depth_gradient) * flips
	var center: Vector2 = projection.view_center
	var distance: float = projection.distance
	var depth: float = spatial.depth
	if spatial.get("follow_camera_x", false):
		world.origin.x += center.x

	# H maps a native local pixel to homogeneous projected world pixels:
	# screen = center + (world.xy - center) * D / (D + world.z).
	var x := distance * world.x + center * gradient.x
	var y := distance * world.y + center * gradient.y
	var origin := distance * world.origin + center * depth
	homography = Basis(
		Vector3(x.x, x.y, gradient.x),
		Vector3(y.x, y.y, gradient.y),
		Vector3(origin.x, origin.y, distance + depth)
	)
	if absf(homography.determinant()) < 1e-12:
		return false  # An exactly edge-on plane has no visible area.
	var inverse := homography.inverse()
	var row := Vector3(inverse.x.z, inverse.y.z, inverse.z.z) * distance
	var axis := Vector2(row.x, row.y)
	inverse_weight = Vector3(
		axis.dot(visual.transform.x),
		axis.dot(visual.transform.y),
		axis.dot(visual.transform.origin) + row.z
	)
	return true


func _clip(vertices: PackedVector4Array, boundary: float, keep_above: bool) -> PackedVector4Array:
	var result := PackedVector4Array()
	if vertices.is_empty():
		return result
	var previous := vertices[-1]
	var previous_depth := _depth(previous)
	var previous_inside := previous_depth >= boundary if keep_above else previous_depth <= boundary
	for current: Vector4 in vertices:
		var current_depth := _depth(current)
		var current_inside := current_depth >= boundary if keep_above else current_depth <= boundary
		if current_inside != previous_inside:
			var fraction := (boundary - previous_depth) / (current_depth - previous_depth)
			result.append(previous.lerp(current, fraction))
		if current_inside:
			result.append(current)
		previous = current
		previous_depth = current_depth
		previous_inside = current_inside
	return result


func _depth(vertex: Vector4) -> float:
	return homography.x.z * vertex.x + homography.y.z * vertex.y + homography.z.z


func _build_triangles(visual: Node2D) -> void:
	sprite_key = visual.current_sprite
	triangles.clear()
	var mesh: Dictionary = visual.effect_mesh
	if not mesh.is_empty():
		texture = visual.effect_texture
		for indices: Array in mesh.triangles:
			var vertices := PackedVector4Array()
			for index: int in indices:
				var point := Assets.vec(mesh.vertices[index])
				var uv := Assets.vec(mesh.uv[index])
				vertices.append(Vector4(point.x, point.y, uv.x, uv.y))
			triangles.append(vertices)
		return

	var atlas: AtlasTexture = visual.source
	texture = atlas.atlas
	if not visual.slice_quads.is_empty():
		for index in range(0, visual.slice_quads.size(), 2):
			var region: Rect2 = visual.slice_quads[index + 1]
			region.position += atlas.region.position
			_append_quad(visual.slice_quads[index], region)
		return
	if int(visual.data.mode) != 2:
		_append_quad(visual.destination, atlas.region)
		return

	# Preserve the existing cropped last tile, including non-integer renderer
	# widths. UVs refer to the actual atlas, not AtlasTexture's implicit remapping.
	var size := atlas.get_size() * (16.0 / float(Assets.sprite_info(sprite_key).ppu))
	var destination: Rect2 = visual.destination
	for y in range(ceili(destination.size.y / size.y)):
		for x in range(ceili(destination.size.x / size.x)):
			var start := Vector2(x, y) * size
			var piece := (destination.size - start).min(size)
			_append_quad(
				Rect2(destination.position + start, piece),
				Rect2(atlas.region.position, piece / size * atlas.region.size)
			)


func _append_quad(rect: Rect2, region: Rect2) -> void:
	var points := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.end,
		rect.position + Vector2(0, rect.size.y)
	]
	var pixels := [
		region.position,
		region.position + Vector2(region.size.x, 0),
		region.end,
		region.position + Vector2(0, region.size.y)
	]
	for indices in [[0, 1, 2], [0, 2, 3]]:
		var vertices := PackedVector4Array()
		for index: int in indices:
			var point: Vector2 = points[index]
			var uv: Vector2 = pixels[index] / texture.get_size()
			vertices.append(Vector4(point.x, point.y, uv.x, uv.y))
		triangles.append(vertices)
