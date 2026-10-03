@tool
extends Node3D
## Two authored model resources, instantiated once. Animation changes one hinge
## transform; the tread and its two gears retain the same meshes for every pose.
const BACKPLATE: PackedScene = preload("Assets/Backplate.blend")
const TREAD: PackedScene = preload("Assets/Tread.blend")
const AlarmVisual = preload("GeometryVisual.gd")
var backplate: Node3D
var tread: Node3D
var hinge: Node3D
var animation: AnimationPlayer
var alarm: MeshInstance3D
var fold_amount := -1.0
# Source frame identity retained for host diagnostics, never used to swap meshes.
var current_key := ""
var _fold_clip: StringName
var _surface_materials: Array[Dictionary] = []
var inspection_materials := false

func setup() -> void:
	if backplate != null:
		return
	backplate = BACKPLATE.instantiate()
	add_child(backplate)
	tread = TREAD.instantiate()
	add_child(tread)
	hinge = _named(tread, "TreadHinge") as Node3D
	alarm = _named(backplate, "AlarmLamp") as MeshInstance3D
	assert(hinge != null and alarm != null, "Model is missing its named hinge or alarm")
	alarm.set_script(AlarmVisual)
	alarm.configure(Color(1.0, 0.0, 0.0, 0.0), 1)
	animation = _animation_player(tread)
	assert(animation != null, "Tread.blend must contain its authored Fold animation")
	for clip: StringName in animation.get_animation_list():
		if String(clip).contains("Fold"):
			_fold_clip = clip
			break
	assert(not _fold_clip.is_empty(), "Imported Fold action was not found")
	# Physics owns the clock. Never let an imported AnimationPlayer race it.
	animation.set_process(false)
	animation.set_physics_process(false)
	_collect_front_materials(backplate)
	_collect_front_materials(tread)
	set_inspection_materials(false)
	set_fold(0.0)

func set_fold(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, fold_amount):
		return
	fold_amount = next
	var clip := animation.get_animation(_fold_clip)
	animation.play(_fold_clip)
	animation.seek(clip.length * fold_amount, true)
	animation.pause()
	if is_inside_tree():
		get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE

static func _named(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var match_node := _named(child, wanted)
		if match_node != null:
			return match_node
	return null

static func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _animation_player(child)
		if found != null:
			return found
	return null


## Gameplay uses authored palette colors rather than environment-dependent PBR.
## Geometry, thickness, normals and Fold animation stay identical in both modes.
## Inspection restores imported lit materials so depth remains easy to inspect.
func _collect_front_materials(node: Node) -> void:
	if node is MeshInstance3D and node != alarm:
		var mesh_node := node as MeshInstance3D
		for surface in range(mesh_node.mesh.get_surface_count()):
			var imported := mesh_node.get_active_material(surface) as StandardMaterial3D
			if imported == null:
				continue
			var palette := imported.duplicate() as StandardMaterial3D
			palette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			palette.metallic = 0.0
			palette.emission_enabled = false
			_surface_materials.append({"mesh": mesh_node, "surface": surface, "lit": imported, "palette": palette})
	for child in node.get_children():
		_collect_front_materials(child)

func set_inspection_materials(enabled: bool) -> void:
	inspection_materials = enabled
	for entry: Dictionary in _surface_materials:
		entry.mesh.set_surface_override_material(entry.surface, entry.lit if enabled else entry.palette)
	if is_inside_tree():
		get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE
