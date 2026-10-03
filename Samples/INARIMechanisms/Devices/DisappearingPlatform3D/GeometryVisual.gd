@tool
extends MeshInstance3D
## One mesh per source layer, never one scene node per pixel.
var current_key := ""
var modulate := Color.WHITE:
	set(value):
		if modulate == value:
			return
		modulate = value
		if material_override != null:
			material_override.albedo_color = value
		if is_inside_tree():
			get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE

func configure(tint: Color, order: int) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.render_priority = order
	material_override = material
	material.albedo_color = tint
	modulate = tint
