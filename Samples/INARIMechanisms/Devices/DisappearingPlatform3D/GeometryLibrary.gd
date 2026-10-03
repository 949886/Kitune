@tool
extends RefCounted
## Exact-color, closed, six-face solids. Front projection reproduces the art;
## the back and side walls remain real geometry when inspected from an angle.
static var _meshes: Dictionary = {}
static var _recipe: Dictionary = {}
const QUADS = [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [4, 5, 1, 0], [3, 2, 6, 7]]

static func recipe(folder: String) -> Dictionary:
	if _recipe.is_empty():
		_recipe = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/geometry.json"))
	return _recipe

static func get_mesh(key: String, folder: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var entry: Dictionary = recipe(folder)[key]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# Platform poses have substantial volume. Backplate and halo are thinner
	# relief layers, also closed solids, not textured billboards.
	var depth := 8.0 if key.begins_with("sharedassets2_") else 2.0
	for box: Array in entry.boxes:
		var x: float = box[0] + entry.offset[0]
		var y: float = -(box[1] + entry.offset[1])
		var w: float = box[2]
		var h: float = box[3]
		var tint := Color(float(box[4]) / 255.0, float(box[5]) / 255.0, float(box[6]) / 255.0, float(box[7]) / 255.0)
		var corners := [Vector3(x,y,0), Vector3(x+w,y,0), Vector3(x+w,y-h,0), Vector3(x,y-h,0), Vector3(x,y,-depth), Vector3(x+w,y,-depth), Vector3(x+w,y-h,-depth), Vector3(x,y-h,-depth)]
		for quad: Array in QUADS:
			var start := vertices.size()
			for corner: int in quad:
				vertices.append(corners[corner])
				colors.append(tint)
			indices.append_array(PackedInt32Array([start,start+1,start+2,start,start+2,start+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = result
	return result
