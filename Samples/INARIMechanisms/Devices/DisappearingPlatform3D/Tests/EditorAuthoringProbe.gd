extends SceneTree
## Run with --headless --editor --script, not the normal runtime probe command.
## Native Editable Children must not acquire runtime palettes, alarm scripts, or
## Fold poses when the editor opens, validates, or saves the device scene.
const Platform = preload("../DisappearingPlatform3D.tscn")
var checks := 0
var failed := false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(all_nodes(child))
	return result


func named(node: Node, wanted: String) -> Node:
	for child: Node in all_nodes(node):
		if String(child.name) == wanted:
			return child
	return null


func material_signature(material: Material) -> Variant:
	if material == null:
		return null
	if material is BaseMaterial3D:
		return [material.get_class(), material.albedo_color, material.shading_mode, material.metallic, material.roughness, material.transparency, material.albedo_texture]
	return material


func snapshot(platform: Node2D) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in all_nodes(platform):
		var values: Dictionary = {"class": node.get_class(), "script": node.get_script()}
		if node is Node3D or node is Node2D:
			values.transform = node.transform
		if node is MeshInstance3D:
			values.mesh = node.mesh
			values.material_override = material_signature(node.material_override)
			var surfaces: Array = []
			for surface in node.mesh.get_surface_count():
				surfaces.append(material_signature(node.get_surface_override_material(surface)))
			values.surface_overrides = surfaces
		if node is AnimationPlayer:
			values.animation = [node.active, node.playback_process_mode, node.autoplay]
		if node is Camera3D:
			values.camera = [node.projection, node.size, node.fov, node.near, node.far]
		if node is SubViewport:
			values.viewport = [node.size, node.transparent_bg]
		if node is CollisionPolygon2D:
			values.polygon = node.polygon.duplicate()
		result[String(platform.get_path_to(node))] = values
	return result


func equivalent(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) != typeof(expected):
		return false
	match typeof(actual):
		TYPE_FLOAT:
			return is_equal_approx(actual, expected)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_COLOR:
			return actual.is_equal_approx(expected)
		TYPE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			if actual.size() != expected.size():
				return false
			for index in actual.size():
				if not equivalent(actual[index], expected[index]):
					return false
			return true
		TYPE_DICTIONARY:
			if actual.size() != expected.size():
				return false
			for key: Variant in expected:
				if not actual.has(key) or not equivalent(actual[key], expected[key]):
					return false
			return true
	return actual == expected


func check_snapshot(platform: Node2D, original: Dictionary, context: String) -> void:
	var current := snapshot(platform)
	check(current.size() == original.size(), context + " added or removed authored nodes")
	for path: String in original:
		check(current.has(path), context + " replaced authored node " + path)
		if not current.has(path):
			continue
		for property_name: String in original[path]:
			check(equivalent(current[path][property_name], original[path][property_name]), context + " changed " + path + " / " + property_name)
	check(platform.mechanism._surface_materials.is_empty(), context + " retained generated gameplay palettes in the editor")
	check(not platform._initialized and not platform.mechanism._initialized, context + " initialized gameplay while editing")


func author_changes(platform: Node2D) -> void:
	platform.set_editable_instance(platform.mechanism.backplate, true)
	platform.set_editable_instance(platform.mechanism.tread, true)
	platform.camera.position = Vector3(13.25, -27.5, 470)
	platform.camera.size = 153.75
	platform.viewport.size = Vector2i(297, 181)
	platform.model.rotation_degrees = Vector3(1, -2, 3)
	platform.mechanism.position = Vector3(5.25, -3.125, 1.5)
	platform.mechanism.backplate.position = Vector3(0.5, -0.75, 1.25)
	platform.mechanism.tread.position = Vector3(-0.25, 0.5, -0.75)
	platform.display.position = Vector2(-114.75, -67.5)
	platform.shape.polygon = PackedVector2Array([Vector2(-43, -3), Vector2(51, -3), Vector2(51, 18), Vector2(-43, 18)])
	var hinge := named(platform.mechanism.tread, "TreadHinge") as Node3D
	hinge.rotation_degrees.x = 12.5
	hinge.position = Vector3(0.125, 0.375, -0.5)
	var frame := named(platform.mechanism.backplate, "FrameBody") as MeshInstance3D
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(0.19, 0.37, 0.59, 1)
	surface.roughness = 0.43
	surface.metallic = 0.21
	frame.set_surface_override_material(0, surface)
	var lamp := named(platform.mechanism.backplate, "AlarmLamp") as MeshInstance3D
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(0.75, 0.2, 0.13, 0.7)
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	lamp.material_override = lamp_material


func check_editor_scene(customized: bool) -> void:
	var platform := Platform.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	if customized:
		author_changes(platform)
	var original := snapshot(platform)
	root.add_child(platform)
	check_snapshot(platform, original, "Editor _ready")
	check(not platform.is_physics_processing(), "Editor enabled platform gameplay physics")
	for iteration in 3:
		platform._ready()
		check(platform.mechanism.setup(), "Editor validation rejected valid model references")
		platform.mechanism.set_fold(0.6)
		platform.enter_inspection()
		check(not platform.is_inspecting(), "Editor entered runtime inspection")
		check_snapshot(platform, original, "Repeated editor setup")
	var packed := PackedScene.new()
	check(packed.pack(platform) == OK, "Editor scene could not be packed")
	var path := "user://editor_authoring_probe_%s.tscn" % Time.get_ticks_usec()
	var saved := ResourceSaver.save(packed, path)
	check(saved == OK, "Editor scene could not be saved")
	if saved == OK:
		var resource := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(resource != null, "Editor-authored scene could not be reloaded")
		if resource != null:
			var restored := resource.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
			check_snapshot(restored, original, "Editor packed save/reload")
			root.add_child(restored)
			check_snapshot(restored, original, "Reloaded editor _ready")
			restored.free()
		check(DirAccess.remove_absolute(path) == OK, "Editor probe could not remove its scratch scene")
	platform.free()


func run() -> void:
	check(Engine.is_editor_hint(), "EditorAuthoringProbe requires --editor; refusing to simulate an editor pass")
	if not Engine.is_editor_hint():
		quit(1)
		return
	# Let the real editor finish its asynchronous startup scan before quitting.
	await create_timer(0.25).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():
		await create_timer(0.05).timeout
	check_editor_scene(false)
	check_editor_scene(true)
	await process_frame
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_EDITOR_AUTHORING_PASS checks=", checks, " editor_hint=", Engine.is_editor_hint())
	quit(1 if failed else 0)
