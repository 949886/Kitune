extends SceneTree
## Native Unity matrices and independent camera-ray intersections check projection.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const NativeProjection = preload("res://Samples/ArtDirection/Runtime/OriginalSceneProjection.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")

var pixels_per_unit: float
var diagnostic := Shader.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var proof: Dictionary = Assets.read_json(Assets.ROOT + "tilted_planes.json")
	pixels_per_unit = proof.pixels_per_unit
	# Keep the production vertex/UV interpolation code. Display UVs only so
	# native noise, emission and transparency cannot hide perspective errors.
	diagnostic.code = (
		Glow.code.get_slice("void fragment()", 0)
		+ """
uniform vec2 probe_uv_origin;
uniform vec2 probe_uv_size;
void fragment() {
	vec2 uv = perspective_uv.xy / perspective_uv.z;
	vec3 value = vec3((uv - probe_uv_origin) / probe_uv_size, 0.0);
	COLOR = vec4(linear_framebuffer ? original_to_linear(value) : value, 1.0);
}
"""
	)
	var total := 0
	for level: String in proof.levels:
		var source: Dictionary = proof.levels[level]
		assert(source.source_sha256.length() == 64)
		var scene: Dictionary = Assets.read_json(Assets.ROOT + level + ".json")
		var selected := {}
		for item: Dictionary in scene.sprites:
			var key := str(int(item.go))
			if not source.world_matrices.has(key):
				continue
			total += 1
			var matrix := _matrix(source.world_matrices[key])
			_verify_geometry(item, matrix)
			# Cover every tilted material plus every shrine jade orientation.
			var group: String = item.material + str(item.mode)
			if level == "level25" or not selected.has(group):
				selected[group] = true
				if DisplayServer.get_name() != "headless" and level != "level2":
					await _verify_pixels(item, matrix)
	assert(total == 538)
	await _verify_scenes()
	print("TILTED_PLANE_PASS")
	quit()


func _matrix(rows: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(rows[0][0], rows[1][0], rows[2][0]),
			Vector3(rows[0][1], rows[1][1], rows[2][1]),
			Vector3(rows[0][2], rows[1][2], rows[2][2])
		),
		Vector3(rows[0][3], rows[1][3], rows[2][3])
	)


func _world(local: Vector2, item: Dictionary, matrix: Transform3D) -> Vector3:
	var flipped := local * Vector2(-1 if item.flip[0] else 1, -1 if item.flip[1] else 1)
	return matrix * Vector3(flipped.x / pixels_per_unit, -flipped.y / pixels_per_unit, 0)


func _project(world: Vector3, center: Vector2, distance: float) -> Vector2:
	var point := Vector2(world.x, -world.y) * pixels_per_unit
	return center + (point - center) * distance / (distance + world.z)


func _verify_geometry(item: Dictionary, matrix: Transform3D) -> void:
	var projection := NativeProjection.new()
	projection.configure(Assets.read_json(Assets.ROOT + "camera.json"))
	var visual := Visual.new()
	# Geometry checks do not need hundreds of material keyword configurations;
	# actual stage construction below separately checks their live materials.
	visual.data = item
	visual.transform = Assets.matrix(item.transform)
	visual.set_animation_sprite(item.sprite)
	visual.material = ShaderMaterial.new()
	visual.material.shader = diagnostic
	projection.register_tilted(visual, item.spatial)
	visual.perspective._build_triangles(visual)
	assert(not visual.perspective.triangles.is_empty())
	for center in [Vector2.ZERO, Vector2(-5200, 4800), Vector2(250, -130)]:
		projection.update_center(center)
		assert(visual.perspective._update_projection(visual))
		for triangle: PackedVector4Array in visual.perspective.triangles:
			for vertex: Vector4 in triangle:
				var local := Vector2(vertex.x, vertex.y)
				var world := _world(local, item, matrix)
				var point: Vector3 = visual.perspective.homography * Vector3(local.x, local.y, 1)
				assert(absf(point.z - (projection.distance + world.z)) < 0.01)
				if point.z <= projection.near_clip:
					continue
				var expected := _project(world, center, projection.distance)
				assert((Vector2(point.x, point.y) / point.z).distance_to(expected) < 0.08)
	visual.free()
	projection.free()


func _verify_pixels(item: Dictionary, matrix: Transform3D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.use_hdr_2d = RenderingServer.get_current_rendering_method() != &"gl_compatibility"
	root.add_child(viewport)
	var projection := NativeProjection.new()
	projection.configure(Assets.read_json(Assets.ROOT + "camera.json"))
	viewport.add_child(projection)
	var visual := Visual.new()
	visual.configure(item)
	visual.material = ShaderMaterial.new()
	visual.material.shader = diagnostic
	visual.material.set_shader_parameter("linear_framebuffer", viewport.use_hdr_2d)
	var bounds := _uv_bounds(visual)
	visual.material.set_shader_parameter("probe_uv_origin", bounds.position)
	visual.material.set_shader_parameter("probe_uv_size", bounds.size)
	viewport.add_child(visual)
	projection.register_tilted(visual, item.spatial)
	visual.perspective._build_triangles(visual)
	var origin := Vector2(matrix.origin.x, -matrix.origin.y) * pixels_per_unit
	var cases := [origin, origin + Vector2(75, -50)]
	# A real shrine quad also exercises polygons intersecting both clipping planes.
	if item.sprite == "sharedassets25_148":
		cases.append(origin)
	for index in cases.size():
		var center: Vector2 = cases[index]
		projection.update_center(center)
		var extent := Vector2.ONE
		var nearest := INF
		var farthest := -INF
		for triangle: PackedVector4Array in visual.perspective.triangles:
			for vertex: Vector4 in triangle:
				var world := _world(Vector2(vertex.x, vertex.y), item, matrix)
				nearest = minf(nearest, projection.distance + world.z)
				farthest = maxf(farthest, projection.distance + world.z)
				extent = extent.max((_project(world, center, projection.distance) - center).abs())
		var zoom := minf(140.0 / extent.x, 75.0 / extent.y)
		viewport.canvas_transform = Transform2D(
			Vector2(zoom, 0), Vector2(0, zoom), Vector2(viewport.size) * 0.5 - center * zoom
		)
		if index == 2:
			projection.near_clip = lerpf(nearest, farthest, 0.25)
			projection.far_clip = lerpf(nearest, farthest, 0.75)
			visual.queue_redraw()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var camera_origin := Vector3(
			center.x / pixels_per_unit, -center.y / pixels_per_unit, -projection.distance
		)
		var normal := matrix.basis.x.cross(matrix.basis.y).normalized()
		var inverse := matrix.affine_inverse()
		var checked := 0
		var mismatches := 0
		var expected_pixels := 0
		var coverage_errors := 0
		for y in range(2, viewport.size.y - 2, 2):
			for x in range(2, viewport.size.x - 2, 2):
				var screen := Vector2(x + 0.5, y + 0.5) - Vector2(viewport.size) * 0.5
				var ray := Vector3(
					screen.x / zoom / pixels_per_unit,
					-screen.y / zoom / pixels_per_unit,
					projection.distance
				)
				var time := normal.dot(matrix.origin - camera_origin) / normal.dot(ray)
				var depth: float = time * projection.distance
				var local3 := inverse * (camera_origin + ray * time)
				var local := Vector2(local3.x, -local3.y) * pixels_per_unit
				local *= Vector2(-1 if item.flip[0] else 1, -1 if item.flip[1] else 1)
				var uv := _expected_uv(visual, local)
				var expected_alpha: bool = (
					uv != Vector2.INF
					and depth > projection.near_clip
					and depth < projection.far_clip
				)
				var pixel := image.get_pixel(x, y)
				expected_pixels += int(expected_alpha)
				coverage_errors += int(expected_alpha != (pixel.a > 0.9))
				# Coverage is checked separately, including the clipped-away region.
				# Compare UVs wherever both the ray and rasterizer hit the plane.
				if not expected_alpha:
					continue
				if pixel.a < 0.9:
					continue
				checked += 1
				if viewport.use_hdr_2d:
					pixel = pixel.linear_to_srgb()
				var expected := (uv - bounds.position) / bounds.size
				if Vector2(pixel.r, pixel.g).distance_to(expected) > 0.012:
					mismatches += 1
		assert(checked > 20, "Native tilted fixture did not render")
		assert(
			coverage_errors <= maxi(8, ceili(expected_pixels * 0.02)),
			"Native plane silhouette or clipping disagrees"
		)
		assert(mismatches == 0, "Perspective UV disagrees with native ray-plane intersection")
		print(
			"TILTED_GPU ",
			int(item.go),
			" case=",
			index,
			" samples=",
			checked,
			" mismatches=",
			mismatches,
			" coverage_errors=",
			coverage_errors
		)
	viewport.queue_free()
	await process_frame


func _uv_bounds(visual: Node) -> Rect2:
	if visual.effect_mesh.is_empty():
		var atlas: AtlasTexture = visual.source
		return Rect2(
			atlas.region.position / atlas.atlas.get_size(),
			atlas.region.size / atlas.atlas.get_size()
		)
	var points: Array = visual.effect_mesh.uv
	var result := Rect2(Assets.vec(points[0]), Vector2.ZERO)
	for point: Array in points:
		result = result.expand(Assets.vec(point))
	return result


func _expected_uv(visual: Node, local: Vector2) -> Vector2:
	var mesh: Dictionary = visual.effect_mesh
	if not mesh.is_empty():
		for triangle: Array in mesh.triangles:
			var a := Assets.vec(mesh.vertices[triangle[0]])
			var b := Assets.vec(mesh.vertices[triangle[1]])
			var c := Assets.vec(mesh.vertices[triangle[2]])
			var barycentric := Transform2D(b - a, c - a, a).affine_inverse() * local
			if barycentric.x >= 0 and barycentric.y >= 0 and barycentric.x + barycentric.y <= 1:
				return (
					Assets.vec(mesh.uv[triangle[0]]) * (1.0 - barycentric.x - barycentric.y)
					+ Assets.vec(mesh.uv[triangle[1]]) * barycentric.x
					+ Assets.vec(mesh.uv[triangle[2]]) * barycentric.y
				)
		return Vector2.INF
	var rect: Rect2 = visual.destination
	if not rect.has_point(local):
		return Vector2.INF
	if not visual.slice_quads.is_empty():
		# Intersect the native plane first, then sample its nine-slice regions.
		# This oracle uses source distances, independently of generated triangles.
		var info: Dictionary = visual.Slicing.definition(visual.current_sprite)
		var border: Array = info.border
		var point := local - rect.position
		var units := pixels_per_unit / float(Assets.sprite_info(visual.current_sprite).ppu)
		var tiled := int(visual.data.mode) == 2
		var native := Vector2(
			_slice_axis(point.x, rect.size.x, info.size[0], border[0], border[2], units, tiled),
			(
				float(info.size[1])
				- _slice_axis(
					rect.size.y - point.y,
					rect.size.y,
					info.size[1],
					border[3],
					border[1],
					units,
					tiled
				)
			)
		)
		var trim := Assets.rect(info.trim)
		if not trim.has_point(native):
			return Vector2.INF
		var bounds := _uv_bounds(visual)
		return bounds.position + (native - trim.position) / trim.size * bounds.size
	var normalized := (local - rect.position) / rect.size
	if int(visual.data.mode) == 2:
		var size: Vector2 = (
			visual.source.get_size()
			* (pixels_per_unit / float(Assets.sprite_info(visual.current_sprite).ppu))
		)
		normalized = (local - rect.position).posmodv(size) / size
	var bounds := _uv_bounds(visual)
	return bounds.position + normalized * bounds.size


func _slice_axis(
	point: float, length: float, pixels: float, first: float, last: float, units: float, tiled: bool
) -> float:
	var scale := minf(1.0, length / ((first + last) * units)) if first + last > 0.0 else 1.0
	var left := first * units * scale
	var right := last * units * scale
	if point < left:
		return point / left * first
	if point >= length - right and right > 0.0:
		return pixels - last + (point - length + right) / right * last
	var center := pixels - first - last
	if tiled:
		return first + fposmod(point - left, center * units) / units
	return first + (point - left) / (length - left - right) * center


func _verify_scenes() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	for index in lab.profiles.size():
		var path: String = lab.profiles[index].get("scene_data", "")
		if path not in ["level15.json", "level25.json"]:
			continue
		lab.load_level(index)
		for frame in 4:
			await process_frame
		assert(lab.stage.projection.tilted_visuals.size() == (271 if path == "level15.json" else 5))
		var materials := {}
		for visual: Node2D in lab.stage.projection.tilted_visuals:
			assert(visual.perspective.projection == lab.stage.projection)
			assert(not materials.has(visual.material.get_instance_id()))
			materials[visual.material.get_instance_id()] = true
		if path == "level25.json":
			assert(lab.water_capture.projection.tilted_visuals.size() == 5)
			for copy: Node2D in lab.water_capture.projection.tilted_visuals:
				assert(copy.perspective.projection == lab.water_capture.projection)
				assert(not materials.has(copy.material.get_instance_id()))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://tmp/art-direction/tilted_" + path + ".png"
			)
	lab.queue_free()
	await process_frame
