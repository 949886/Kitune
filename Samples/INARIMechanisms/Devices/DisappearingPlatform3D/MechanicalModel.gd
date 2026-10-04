@tool
extends Node3D
## Bind the model instances authored in the scene. Animation changes one hinge
## transform; the tread and its two gears retain the same meshes for every pose.
@export var backplate: Node3D
@export var tread: Node3D
@export var alarm_visual_script: Script
var hinge: Node3D
var animation: AnimationPlayer
var alarm: MeshInstance3D
var fold_amount := -1.0
# Source frame identity retained for host diagnostics, never used to swap meshes.
var current_key := ""
var _fold_clip: StringName
var _surface_materials: Array[Dictionary] = []
var inspection_materials := false
var _initialized := false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(backplate) or not is_instance_valid(tread):
		warnings.append("Assign the scene's Backplate and Tread nodes to this assembly.")
	elif backplate == tread or not is_ancestor_of(backplate) or not is_ancestor_of(tread):
		warnings.append("Backplate and Tread must be distinct children of this assembly.")
	if alarm_visual_script == null:
		var lamp := _named(backplate, "AlarmLamp") if is_instance_valid(backplate) else null
		if lamp == null or lamp.get_script() == null:
			warnings.append("Assign the alarm visual script here or on the imported AlarmLamp.")
	return warnings


func setup() -> bool:
	if _initialized:
		if not is_instance_valid(backplate) or not is_instance_valid(tread) or not is_instance_valid(hinge) or not is_instance_valid(alarm) or not is_instance_valid(animation):
			return _setup_error("An initialized model node was removed; restore the authored assembly before setup.")
		return true
	if not is_instance_valid(backplate) or not is_instance_valid(tread):
		return _setup_error("Assign the authored Backplate and Tread nodes in the Inspector.")
	if backplate == tread or not is_ancestor_of(backplate) or not is_ancestor_of(tread):
		return _setup_error("Backplate and Tread must be distinct children of this assembly.")
	if _named_count(tread, "TreadHinge") != 1:
		return _setup_error("The assigned Tread scene must contain exactly one TreadHinge.")
	if _named_count(backplate, "AlarmLamp") != 1:
		return _setup_error("The assigned Backplate scene must contain exactly one AlarmLamp.")
	hinge = _named(tread, "TreadHinge") as Node3D
	alarm = _named(backplate, "AlarmLamp") as MeshInstance3D
	if hinge == null:
		return _setup_error("The assigned Tread scene is missing its TreadHinge Node3D.")
	if alarm == null:
		return _setup_error("The assigned Backplate scene is missing its AlarmLamp MeshInstance3D.")
	animation = _animation_player(tread)
	if animation == null:
		return _setup_error("The assigned Tread scene must contain an AnimationPlayer.")
	var fold_actions: Array[Dictionary] = []
	_collect_fold_actions(tread, fold_actions)
	if fold_actions.size() != 1:
		return _setup_error("The assigned Tread scene must contain exactly one Fold animation.")
	animation = fold_actions[0].player
	_fold_clip = fold_actions[0].clip
	if animation.get_animation(_fold_clip).length <= 0.0:
		return _setup_error("The assigned Tread AnimationPlayer must contain a nonempty Fold animation.")
	var lamp_script: Script = alarm.get_script()
	if lamp_script == null:
		lamp_script = alarm_visual_script
	if lamp_script == null or (lamp_script.get_instance_base_type() != &"MeshInstance3D" and not ClassDB.is_parent_class(lamp_script.get_instance_base_type(), "MeshInstance3D")):
		return _setup_error("Assign a MeshInstance3D alarm visual script to this assembly or its AlarmLamp.")
	if not _script_has_member(lamp_script, "configure", true) or not _script_has_member(lamp_script, "modulate", false):
		return _setup_error("The alarm visual script must provide configure() and a modulate color.")
	# Preserve authored lamp colors/textures, but isolate its animated alpha from
	# other scene instances. The default imported lamp uses the original red tint.
	var lamp_material: Material = alarm.material_override
	if lamp_material == null and alarm.mesh != null and alarm.mesh.get_surface_count() > 0:
		lamp_material = alarm.get_surface_override_material(0)
	if lamp_material != null and not lamp_material is BaseMaterial3D:
		return _setup_error("AlarmLamp material overrides must support the BaseMaterial3D albedo color for alpha animation.")
	# The editor owns these serialized nodes. Runtime palettes and lamp scripts
	# must never become saved Editable Children overrides or hide material edits.
	if Engine.is_editor_hint():
		return true
	if alarm.get_script() == null:
		alarm.set_script(lamp_script)
	if lamp_material != null:
		var local_material := lamp_material.duplicate() as BaseMaterial3D
		local_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		alarm.material_override = local_material
		var tint := local_material.albedo_color
		tint.a = 0.0
		alarm.set("modulate", tint)
	else:
		alarm.call("configure", Color(1.0, 0.0, 0.0, 0.0), 1)
	# Physics owns the clock. Never let an imported AnimationPlayer race it.
	animation.set_process(false)
	animation.set_physics_process(false)
	_surface_materials.clear()
	_collect_front_materials(backplate)
	_collect_front_materials(tread)
	_initialized = true
	set_inspection_materials(false)
	set_fold(0.0)
	return true


func _setup_error(message: String) -> bool:
	push_error("MechanicalModel: " + message)
	return false


static func _script_has_member(script: Script, member: String, method: bool) -> bool:
	while script != null:
		var members: Array[Dictionary] = script.get_script_method_list() if method else script.get_script_property_list()
		for entry: Dictionary in members:
			if entry.name == member:
				return true
		script = script.get_base_script()
	return false

func set_fold(value: float) -> void:
	if not _initialized:
		return
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, fold_amount):
		return
	fold_amount = next
	var clip := animation.get_animation(_fold_clip)
	animation.play(_fold_clip)
	animation.seek(clip.length * fold_amount, true)
	animation.pause()
	_request_redraw()

static func _named(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var match_node := _named(child, wanted)
		if match_node != null:
			return match_node
	return null


static func _named_count(node: Node, wanted: String) -> int:
	var count := 1 if String(node.name) == wanted else 0
	for child: Node in node.get_children():
		count += _named_count(child, wanted)
	return count


static func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _animation_player(child)
		if found != null:
			return found
	return null


static func _collect_fold_actions(node: Node, actions: Array[Dictionary]) -> void:
	if node is AnimationPlayer:
		for clip: StringName in node.get_animation_list():
			if String(clip).contains("Fold"):
				actions.append({"player": node, "clip": clip})
	for child: Node in node.get_children():
		_collect_fold_actions(child, actions)


## Gameplay uses authored palette colors rather than environment-dependent PBR.
## Geometry, thickness, normals and Fold animation stay identical in both modes.
## Inspection restores the exact authored overrides, including an empty override
## for materials supplied by the imported mesh. No shared material is modified.
func _collect_front_materials(node: Node) -> void:
	if node is MeshInstance3D and node != alarm:
		var mesh_node := node as MeshInstance3D
		if mesh_node.material_override != null:
			var authored := mesh_node.material_override as BaseMaterial3D
			if authored != null:
				_surface_materials.append({"mesh": mesh_node, "surface": 0, "whole_mesh": true, "lit": authored, "original_override": authored, "palette": _palette_material(authored)})
		elif mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var authored := mesh_node.get_active_material(surface) as BaseMaterial3D
				if authored == null:
					continue
				_surface_materials.append({"mesh": mesh_node, "surface": surface, "whole_mesh": false, "lit": authored, "original_override": mesh_node.get_surface_override_material(surface), "palette": _palette_material(authored)})
	for child in node.get_children():
		_collect_front_materials(child)


static func _palette_material(authored: BaseMaterial3D) -> BaseMaterial3D:
	var palette := authored.duplicate() as BaseMaterial3D
	palette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	palette.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	palette.metallic = 0.0
	palette.emission_enabled = false
	return palette


func set_inspection_materials(enabled: bool) -> void:
	inspection_materials = enabled
	for entry: Dictionary in _surface_materials:
		if entry.whole_mesh:
			entry.mesh.material_override = entry.original_override if enabled else entry.palette
		else:
			entry.mesh.set_surface_override_material(entry.surface, entry.original_override if enabled else entry.palette)
	_request_redraw()


func _request_redraw() -> void:
	if is_inside_tree() and get_viewport() is SubViewport:
		(get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
