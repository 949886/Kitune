@tool
extends RefCounted
## Native Blender asset is the single geometry source. Godot's editor imports
## .blend through its standard glTF pipeline; exported games need no Blender.
## Names identify the 13 poses and 3 supporting meshes. Meshes are immutable
## shared resources; per-instance tint/alpha stay on GeometryVisual materials.
const MODEL: PackedScene = preload("Assets/DisappearingPlatform3D.blend")
static var _meshes: Dictionary = {}
static var _watching_import := false

static func _invalidate() -> void:
	_meshes.clear()

static func _collect(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_meshes[String(node.name)] = _merge_palette_surfaces(node.mesh)
	for child in node.get_children():
		_collect(child)

static func get_mesh(key: String, _folder: String = "") -> ArrayMesh:
	if not _watching_import:
		MODEL.changed.connect(_invalidate)
		_watching_import = true
	if _meshes.is_empty():
		var source := MODEL.instantiate()
		_collect(source)
		source.free()
	assert(_meshes.has(key), "Missing named mesh in DisappearingPlatform3D.blend: " + key)
	return _meshes.get(key)


## glTF vertex colors are linear and Godot stores vertex channels in 8 bits.
## Keeping the authored colors as palette materials during import avoids losing
## dark sRGB steps. Merge those imported surfaces once into one draw surface;
## positions/indices are copied from Blender, never reconstructed from pixels.
static func _merge_palette_surfaces(source: Mesh) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := source.surface_get_material(surface) as BaseMaterial3D
		assert(material != null, "Blender palette surface needs a material")
		# sRGB -> linear -> sRGB import has float roundoff. Snap the palette
		# back to its authored 8-bit grid before Godot packs vertex channels.
		var color := material.albedo_color
		color = Color8(roundi(color.r*255), roundi(color.g*255), roundi(color.b*255), roundi(color.a*255))
		var offset := vertices.size()
		vertices.append_array(positions)
		for _vertex in positions.size():
			colors.append(color)
		if triangles.is_empty():
			for index in positions.size():
				indices.append(offset + index)
		else:
			for index in triangles:
				indices.append(offset + index)
	var merged := []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = vertices
	merged[Mesh.ARRAY_COLOR] = colors
	merged[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	return mesh
