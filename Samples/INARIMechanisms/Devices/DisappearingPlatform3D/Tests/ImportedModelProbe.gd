extends SceneTree
## CPU projection audit of actual meshes imported from the .blend. This is NOT
## a GPU screenshot. Output images are for source RGBA comparison only.
const Geometry = preload("../GeometryLibrary.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	assert(Geometry.MODEL.resource_path.ends_with(".blend"))
	var folder: String = get_script().resource_path.get_base_dir().get_base_dir()
	assert(not FileAccess.file_exists(folder + "/Assets/geometry.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/device.json"))
	var output := OS.get_environment("INARI_IMPORTED_AUDIT")
	if output.is_empty():
		output = OS.get_user_data_dir().path_join("imported-model-audit")
	DirAccess.make_dir_recursive_absolute(output)
	for key: String in data.sprites:
		var entry: Dictionary = data.sprites[key]
		var mesh := Geometry.get_mesh(key)
		assert(mesh.get_surface_count() == 1)
		var arrays := mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var img := Image.create(entry.size[0], entry.size[1], false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		for t in range(0, indices.size(), 3):
			var a := positions[indices[t]]
			var b := positions[indices[t+1]]
			var c := positions[indices[t+2]]
			if absf(a.z)>0.001 or absf(b.z)>0.001 or absf(c.z)>0.001:
				continue
			var v0 := Vector2(a.x-entry.offset[0], -a.y-entry.offset[1]).round()
			var v1 := Vector2(b.x-entry.offset[0], -b.y-entry.offset[1]).round()
			var v2 := Vector2(c.x-entry.offset[0], -c.y-entry.offset[1]).round()
			var minimum := v0.min(v1).min(v2).round()
			var maximum := v0.max(v1).max(v2).round()
			for y in range(int(minimum.y), int(maximum.y)):
				for x in range(int(minimum.x), int(maximum.x)):
					if inside_triangle(Vector2(x+0.5,y+0.5), v0, v1, v2):
						img.set_pixel(x,y,colors[indices[t]])
		assert(img.save_png(output.path_join(key+".png")) == OK)
	print("IMPORTED_BLEND_MESH_CPU_PROJECTION_PASS: ",output)
	quit()

func inside_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var x := (b-a).cross(p-a)
	var y := (c-b).cross(p-b)
	var z := (a-c).cross(p-c)
	return (x >= -0.01 and y >= -0.01 and z >= -0.01) or (x <= 0.01 and y <= 0.01 and z <= 0.01)
