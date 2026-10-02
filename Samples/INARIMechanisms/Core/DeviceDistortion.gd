@tool
extends MeshInstance2D
## Source SpriteRenderer's tight mesh, UVs and screen-refraction material.
## Using the white Circle texture as a normal sprite would occlude the actor.
const DistortionShader = preload("SquareDistortion.gdshader")
var data: Dictionary
var sprite_library: Dictionary = {}
var animation_offset := Vector2.ZERO
var base_scale := Vector2.ONE


func configure(record: Dictionary, _info: Dictionary, _folder: String) -> void:
	data = record
	var source: Dictionary = record.square_distortion
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for point: Array in source.positions:
		vertices.append(Vector3(point[0], point[1], 0))
	for point: Array in source.uvs:
		uvs.append(Vector2(point[0], point[1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(source.indices)
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = surface
	var pose: Array = record.transform
	transform = Transform2D(
		Vector2(pose[0], pose[1]), Vector2(pose[2], pose[3]), Vector2(pose[4], pose[5])
	)
	base_scale = scale
	var shader_material := ShaderMaterial.new()
	shader_material.shader = DistortionShader
	var parameters: Dictionary = source.parameters
	for pair in [
		["distortion_strength", "_DistortionStrength"],
		["distortion_range", "_DistortionRange"],
		["distortion_scale", "_DistortionScale"],
		["distortion_softness", "_DistortionSoftness"],
		["twirl_strength", "_TwirlStrength"]
	]:
		shader_material.set_shader_parameter(pair[0], parameters[pair[1]])
	shader_material.set_shader_parameter("flow_speed", Vector2(source.flow.r, source.flow.g))
	material = shader_material
	visible = record.get("visible", true)


func set_source_property(property: String, value: float) -> void:
	match property:
		"m_LocalScale.x":
			scale.x = base_scale.x * value / float(data.square_distortion.initial_scale[0])
		"m_LocalScale.y":
			scale.y = base_scale.y * value / float(data.square_distortion.initial_scale[1])
		"material._DistortionStrength":
			material.set_shader_parameter("distortion_strength", value)


func set_animation_visibility(value: bool) -> void:
	visible = value
