extends SceneTree
## The device stores a generic Projection configuration and a model scene, not
## generated viewports/cameras/sprites. Editable source models remain native.
## Scratch scenes are saved under user:// and removed after the probe.
const Platform = preload("../DisappearingPlatform3D.tscn")
const Assembly = preload("../MechanicalAssembly.tscn")
const Preview = preload("../Examples/Preview.tscn")
const CORE_PATHS := {
	"projection": "Projection",
	"solid": "SolidBody2D",
	"shape": "SolidBody2D/CollisionPolygon2D",
	"audio": "ActivationAudio",
}
const PROJECTION_PROPERTIES := [
	"viewport_size", "viewport_update_mode", "camera_size", "camera_position",
	"camera_rotation", "camera_keep_aspect", "camera_near", "camera_far",
	"sprite_position", "sprite_centered", "sprite_texture_filter", "scene_transform",
	"light_rotation", "light_color", "light_energy", "light_shadow_enabled",
]
const ALTERNATE_SOURCE := "level23_7082_0"
var checks := 0
var failed := false
var scratch_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children(true):
		result.append_array(all_nodes(child))
	return result


func named(node: Node, wanted: String) -> Node:
	for child: Node in all_nodes(node):
		if String(child.name) == wanted:
			return child
	return null


func make_unready() -> Node2D:
	var platform: Node2D = Platform.instantiate()
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	return platform


func start(platform: Node2D) -> void:
	root.add_child(platform)
	platform.set_physics_process(false)


func is_exported(object: Object, property_name: String, expected_type: int) -> bool:
	for entry: Dictionary in object.get_property_list():
		if entry.name == property_name:
			return entry.type == expected_type and (entry.usage & PROPERTY_USAGE_EDITOR) != 0 and (entry.usage & PROPERTY_USAGE_STORAGE) != 0
	return false


func check_packed_shell(packed: PackedScene, context: String) -> void:
	var state := packed.get_state()
	check(state.get_node_count() == 5, context + " stored generated projection nodes or lost authored nodes")
	for index in state.get_node_count():
		var type := state.get_node_type(index)
		check(type not in [&"SubViewport", &"Camera3D", &"Sprite2D", &"DirectionalLight3D", &"Node3D"], context + " serialized a generated " + String(type))
		for property_index in state.get_node_property_count(index):
			var property_name := state.get_node_property_name(index, property_index)
			check(property_name not in [&"viewport", &"camera", &"display", &"model", &"mechanism"], context + " persisted a generated runtime reference " + String(property_name))


func check_serialized_scene(platform: Node2D) -> bool:
	check_packed_shell(Platform, "Default device")
	var valid := true
	for property_name: String in CORE_PATHS:
		var child: Node = platform.get_node_or_null(CORE_PATHS[property_name])
		check(child != null, "Authored node is absent before _ready: " + CORE_PATHS[property_name])
		check(is_exported(platform, property_name, TYPE_OBJECT), "Authored node reference is not exported: " + property_name)
		check(platform.get(property_name) == child and child != null, "Authored reference is not resolved before _ready: " + property_name)
		if child != null:
			check(child.owner == platform, "Authored node is not owned by the packed scene: " + property_name)
		else:
			valid = false
	if not valid:
		return false
	check(platform.projection is Node2D, "Projection must be a generic Node2D")
	check(platform.projection.get_child_count() == 0, "Projection exposes its generated render shell in the authored tree")
	check(is_exported(platform.projection, "scene", TYPE_OBJECT) and platform.projection.scene is PackedScene, "Projection scene must be an exported PackedScene")
	check(platform.projection.scene.resource_path.ends_with("/MechanicalAssembly.tscn"), "Device does not inject the standalone authored model scene")
	for property_name: String in PROJECTION_PROPERTIES:
		check(is_exported(platform.projection, property_name, typeof(platform.projection.get(property_name))), "Projection configuration is not persisted in the Inspector: " + property_name)
	var assembly: Node3D = platform.projection.scene.instantiate()
	check(assembly.position == Vector3.ZERO, "Source layout offset belongs to Projection.scene_transform, not the mechanical scene root")
	for property_name: String in ["backplate", "tread"]:
		var part: Node3D = assembly.get(property_name)
		check(is_exported(assembly, property_name, TYPE_OBJECT), "Imported model reference is not editor-visible: " + property_name)
		check(part != null, "Standalone mechanical scene is missing " + property_name)
		if part == null:
			valid = false
			continue
		check(part.get_parent() == assembly, "Imported model was not authored under MechanicalAssembly")
		var filename := "Backplate.blend" if property_name == "backplate" else "Tread.blend"
		check(part.scene_file_path.ends_with("/" + filename), "Model does not retain its native .blend scene reference: " + property_name)
	assembly.free()
	check(is_exported(platform, "source_data", TYPE_OBJECT) and platform.source_data is JSON, "Source data must be an exported JSON resource")
	check(is_exported(platform, "auto_apply_source_layout", TYPE_BOOL), "Automatic preset-layout opt-out is not exported")
	check(is_exported(platform, "layout_source_key", TYPE_STRING), "Authored source-layout key is not exported")
	check(platform.auto_apply_source_layout and platform.layout_source_key == platform.settings.source_key, "Default scene would overwrite its authored layout on _ready")
	return valid


func save_scene(scene: Node, prefix: String) -> PackedScene:
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, prefix + " could not be packed")
	var path := "user://%s_%s.tscn" % [prefix, Time.get_ticks_usec()]
	if ResourceSaver.save(packed, path) != OK:
		check(false, prefix + " could not be saved")
		return null
	scratch_paths.append(path)
	var reloaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(reloaded != null, prefix + " could not be reloaded")
	return reloaded


func authored_model_scene() -> PackedScene:
	var assembly := Assembly.instantiate() as Node3D
	assembly.position = Vector3(5.25, -3.125, 1.5)
	assembly.rotation = Vector3(0.0, 0.02, 0.01)
	assembly.backplate.position = Vector3(0.5, -0.75, 1.25)
	assembly.tread.position = Vector3(-0.25, 0.5, -0.75)
	var packed := save_scene(assembly, "authored_mechanical_model")
	assembly.free()
	return packed


func author_changes(platform: Node2D) -> void:
	platform.projection.viewport_size = Vector2i(311, 227)
	platform.projection.camera_position = Vector3(17, -9, 480)
	platform.projection.camera_size = 187.35
	platform.projection.camera_rotation = Vector3(0.03, -0.07, 0.01)
	platform.projection.camera_keep_aspect = Camera3D.KEEP_WIDTH
	platform.projection.camera_near = 0.25
	platform.projection.camera_far = 777.0
	platform.projection.viewport_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	platform.projection.environment = Environment.new()
	platform.projection.environment.resource_local_to_scene = true
	platform.projection.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	platform.projection.environment.ambient_light_color = Color(0.17, 0.39, 0.58, 1)
	platform.projection.environment.ambient_light_energy = 0.37
	platform.projection.light_rotation = Vector3(-0.54, -0.29, 0.1)
	platform.projection.light_color = Color(0.73, 0.81, 0.95, 1)
	platform.projection.light_energy = 0.625
	platform.projection.light_shadow_enabled = true
	platform.projection.modulate = Color(0.9, 0.8, 0.7, 0.6)
	platform.projection.scene_transform = Transform3D(Basis.from_euler(Vector3(0.02, 0.04, -0.03)).scaled(Vector3(0.95, 1.1, 1.05)), Vector3(3, -7, 2))
	platform.projection.sprite_position = Vector2(-114.75, -67.5)
	platform.projection.sprite_centered = true
	platform.projection.sprite_texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	platform.projection.scene = authored_model_scene()
	platform.solid.position = Vector2(8.25, -2.5)
	platform.solid.rotation = 0.03
	platform.solid.collision_layer = 5
	platform.solid.collision_mask = 12
	platform.shape.position = Vector2(2.5, -1.25)
	platform.shape.polygon = PackedVector2Array([Vector2(-43.5, -3.25), Vector2(51.25, -3.25), Vector2(51.25, 18.5), Vector2(-43.5, 18.5)])
	platform.audio.stream = AudioStreamWAV.new()
	platform.audio.stream.resource_local_to_scene = true
	platform.audio.stream.format = AudioStreamWAV.FORMAT_8_BITS
	platform.audio.stream.mix_rate = 22050
	platform.audio.stream.data = PackedByteArray([0, 16, 32, 64, 32, 16, 0, 0])
	platform.audio.volume_db = -13.5
	platform.audio.pitch_scale = 1.125
	platform.audio.max_polyphony = 3
	platform.settings.disappear_delay = 2.75
	platform.settings.hidden_seconds = 3.5


func snapshot(platform: Node2D) -> Dictionary:
	var projection_values: Array = []
	for property_name: String in PROJECTION_PROPERTIES:
		projection_values.append(platform.projection.get(property_name))
	return {
		"projection": projection_values,
		"projection_node": [platform.projection.transform, platform.projection.modulate],
		"environment": [platform.projection.environment.ambient_light_color, platform.projection.environment.ambient_light_energy],
		"scene": platform.projection.scene.resource_path,
		"solid": [platform.solid.transform, platform.solid.collision_layer, platform.solid.collision_mask],
		"shape": [platform.shape.transform, platform.shape.polygon.duplicate()],
		"audio": [platform.audio.stream.get_class(), platform.audio.stream.data.duplicate(), platform.audio.stream.mix_rate, platform.audio.volume_db, platform.audio.pitch_scale, platform.audio.max_polyphony],
		"settings": [platform.settings.source_key, platform.settings.disappear_delay, platform.settings.hidden_seconds, platform.settings.sound_enabled],
		"source_data": platform.source_data.resource_path,
	}


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
	return actual == expected


func check_snapshot(platform: Node2D, original: Dictionary, context: String) -> void:
	var current := snapshot(platform)
	for property_name: String in original:
		check(equivalent(current[property_name], original[property_name]), context + " overwrote authored " + property_name)


func check_generated_projection(platform: Node2D, context: String) -> void:
	check(platform.viewport == platform.projection.viewport, context + " lost the generated viewport binding")
	check(platform.camera == platform.projection.camera, context + " lost the generated camera binding")
	check(platform.display == platform.projection.sprite, context + " lost the generated sprite binding")
	check(platform.model == platform.projection.scene_container and platform.mechanism == platform.projection.scene_instance, context + " lost the generated model bindings")
	check(platform.viewport.size == platform.projection.viewport_size, context + " ignored authored viewport size")
	check(platform.camera.position.is_equal_approx(platform.projection.camera_position) and is_equal_approx(platform.camera.size, platform.projection.camera_size), context + " ignored authored camera framing")
	check(platform.camera.rotation.is_equal_approx(platform.projection.camera_rotation), context + " ignored authored camera rotation")
	check(platform.camera.keep_aspect == platform.projection.camera_keep_aspect and is_equal_approx(platform.camera.near, platform.projection.camera_near) and is_equal_approx(platform.camera.far, platform.projection.camera_far), context + " ignored authored camera settings")
	check(platform.viewport.transparent_bg and platform.viewport.own_world_3d and platform.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, context + " violated the transparent orthographic projection contract")
	check(platform.camera.environment != platform.projection.environment, context + " reused the authored Environment template directly")
	check(platform.camera.environment.ambient_light_color.is_equal_approx(platform.projection.environment.ambient_light_color) and is_equal_approx(platform.camera.environment.ambient_light_energy, platform.projection.environment.ambient_light_energy), context + " ignored the authored Environment template")
	check(platform.display.position.is_equal_approx(platform.projection.sprite_position), context + " ignored authored sprite position")
	check(platform.display.centered == platform.projection.sprite_centered and platform.display.texture_filter == platform.projection.sprite_texture_filter, context + " ignored authored sprite settings")
	var light: DirectionalLight3D = platform.projection.light
	check(light.rotation.is_equal_approx(platform.projection.light_rotation) and light.light_color.is_equal_approx(platform.projection.light_color) and is_equal_approx(light.light_energy, platform.projection.light_energy) and light.shadow_enabled == platform.projection.light_shadow_enabled, context + " ignored authored directional lighting")
	check(platform.model.transform.is_equal_approx(platform.projection.scene_transform), context + " ignored authored model-container transform")
	check(platform.projection.get_child_count() == 0, context + " exposed generated render nodes in the authored tree")
	var authored := platform.projection.scene.instantiate() as Node3D
	check(platform.mechanism.transform.is_equal_approx(authored.transform), context + " changed the injected model transform")
	check(platform.mechanism.backplate.transform.is_equal_approx(authored.backplate.transform), context + " changed the injected Backplate transform")
	check(platform.mechanism.tread.transform.is_equal_approx(authored.tread.transform), context + " changed the injected Tread transform")
	authored.free()


func node_ids(platform: Node2D) -> Array[int]:
	var result: Array[int] = []
	for node: Node in all_nodes(platform):
		result.append(node.get_instance_id())
	return result


func check_idempotence(platform: Node2D, original: Dictionary) -> void:
	var identities := node_ids(platform)
	var audio_stream: AudioStream = platform.audio.stream
	var source_data: JSON = platform.source_data
	var model_scene: PackedScene = platform.projection.scene
	var palette_ids: Array[int] = []
	for entry: Dictionary in platform.mechanism._surface_materials:
		palette_ids.append(entry.palette.get_instance_id())
	var alarm_material: Material = platform.mechanism.alarm.material_override
	check(platform.activate(), "Authored scene did not activate before idempotence checks")
	platform.advance(0.125)
	var clocks: Array = [platform.state, platform.elapsed, platform._animation_index, platform._animation_time]
	for iteration in 4:
		check(platform.projection.ensure_built(), "Repeated projection setup failed")
		check(platform.mechanism.setup(), "Repeated mechanical setup failed")
		platform._ready()
		platform.set_physics_process(false)
		check_snapshot(platform, original, "Repeated setup/_ready")
		check_generated_projection(platform, "Repeated setup/_ready")
		check([platform.state, platform.elapsed, platform._animation_index, platform._animation_time] == clocks, "Repeated _ready restarted active gameplay state or clocks")
		check(node_ids(platform) == identities, "Repeated setup created, replaced, or reordered generated nodes")
		check(platform.audio.stream == audio_stream and platform.source_data == source_data and platform.projection.scene == model_scene, "Repeated setup replaced an authored resource")
		check(platform.mechanism.alarm.material_override == alarm_material, "Repeated setup recreated the instance alarm material")
		var current_palettes: Array[int] = []
		for entry: Dictionary in platform.mechanism._surface_materials:
			current_palettes.append(entry.palette.get_instance_id())
		check(current_palettes == palette_ids, "Repeated setup recreated or multiplied material overrides")
	platform.reset()


func check_independence(platform: Node2D) -> void:
	var other := make_unready()
	start(other)
	check(platform.viewport != other.viewport and platform.viewport.get_texture() != other.viewport.get_texture(), "Instances share a viewport or its texture")
	check(platform.display.texture != other.display.texture, "Instances share generated ViewportTexture resources")
	check(platform.display.texture.get_size() == Vector2(platform.viewport.size) and other.display.texture.get_size() == Vector2(other.viewport.size), "A generated ViewportTexture targets the wrong instance")
	check(platform.mechanism.backplate != other.mechanism.backplate and platform.mechanism.tread != other.mechanism.tread, "Instances share model nodes")
	check(platform.mechanism.alarm.material_override != other.mechanism.alarm.material_override, "Alarm material leaks between instances")
	var untouched: Transform3D = other.mechanism.hinge.transform
	platform.mechanism.set_fold(0.45)
	check(other.mechanism.hinge.transform == untouched, "Changing one instance folds the other's imported hinge")
	platform.enter_inspection()
	check(not other.mechanism.inspection_materials and not other.is_inspecting(), "Inspection changed the other instance")
	for index in platform.mechanism._surface_materials.size():
		check(platform.mechanism._surface_materials[index].palette != other.mechanism._surface_materials[index].palette, "Gameplay palette material leaks between instances")
	platform.exit_inspection()
	platform.reset()
	other.free()


func check_authored_material(platform: Node2D) -> void:
	check(platform.projection.ensure_built(), "Projection could not build before device _ready")
	var assembly: Node3D = platform.projection.scene_instance
	var part := named(assembly.backplate, "FrameBody") as MeshInstance3D
	check(part != null, "Imported FrameBody missing before runtime setup")
	if part == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.35, 0.57, 1)
	material.roughness = 0.43
	material.metallic = 0.21
	part.set_surface_override_material(0, material)
	var mesh_resource: Mesh = part.mesh
	var transform_before: Transform3D = part.transform
	var identities := node_ids(platform)
	start(platform)
	check(node_ids(platform) == identities, "Device _ready rebuilt an already prepared Projection")
	check(part.mesh == mesh_resource and part.transform == transform_before, "Setup replaced or transformed authored mesh geometry")
	check(part.get_active_material(0).albedo_color == material.albedo_color, "Gameplay palette discarded authored surface color")
	platform.enter_inspection()
	check(part.get_active_material(0) == material, "Inspection does not restore the authored surface override resource")
	platform.exit_inspection()
	check(material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and is_equal_approx(material.metallic, 0.21), "Runtime modified the source material instead of an instance override")


func check_round_trip(platform: Node2D, original: Dictionary) -> Node2D:
	var reloaded := save_scene(platform, "scene_authoring_probe")
	if reloaded == null:
		return null
	check_packed_shell(reloaded, "Edited device")
	var restored := reloaded.instantiate() as Node2D
	check_snapshot(restored, original, "Packed scene save/reload before _ready")
	start(restored)
	check_snapshot(restored, original, "Packed scene save/reload runtime _ready")
	check_generated_projection(restored, "Packed scene save/reload runtime _ready")
	check(restored._initialized, "Reloaded authored scene did not initialize")
	var runtime_saved := PackedScene.new()
	check(runtime_saved.pack(restored) == OK, "Runtime scene could not be packed")
	check_packed_shell(runtime_saved, "Runtime-built device")
	return restored


func source_layout_snapshot(platform: Node2D) -> Array:
	return [platform.projection.viewport_size, platform.projection.camera_position, platform.projection.camera_size, platform.projection.sprite_position, platform.projection.scene_transform.origin, platform.shape.polygon.duplicate()]


func check_source_layout() -> void:
	var baseline := make_unready()
	baseline.settings.source_key = ALTERNATE_SOURCE
	start(baseline)
	check(baseline.layout_source_key == ALTERNATE_SOURCE, "Preset switch did not record its applied source key")
	var expected := source_layout_snapshot(baseline)
	var manual := make_unready()
	author_changes(manual)
	manual.settings.source_key = ALTERNATE_SOURCE
	manual.auto_apply_source_layout = false
	var original := snapshot(manual)
	start(manual)
	check_snapshot(manual, original, "Disabled automatic source layout")
	check(manual.layout_source_key != ALTERNATE_SOURCE, "Disabled auto layout incorrectly marked the preset as applied")
	var model_scene: PackedScene = manual.projection.scene
	var scene_basis: Basis = manual.projection.scene_transform.basis
	manual.apply_source_layout()
	check(equivalent(source_layout_snapshot(manual), expected), "Explicit source layout did not match the alternate preset")
	check(manual.layout_source_key == ALTERNATE_SOURCE, "Explicit source layout did not record the source key")
	check(manual.projection.scene == model_scene, "Explicit source layout unexpectedly replaced the authored model scene")
	check(manual.projection.scene_transform.basis.is_equal_approx(scene_basis), "Explicit source layout unexpectedly reset the authored model basis")
	check(manual.audio.volume_db == original.audio[3], "Explicit source layout unexpectedly reset audio properties")
	manual.projection.camera_position += Vector3(7, 8, 0)
	manual.shape.polygon = PackedVector2Array([Vector2(-10, 0), Vector2(12, 0), Vector2(12, 9), Vector2(-10, 9)])
	manual.auto_apply_source_layout = true
	var changed := source_layout_snapshot(manual)
	manual._ready()
	manual.set_physics_process(false)
	check(equivalent(source_layout_snapshot(manual), changed), "Matching source key failed to preserve subsequent manual edits")
	baseline.free()
	manual.free()


func check_source_resource() -> void:
	var platform := make_unready()
	var original_resource: JSON = platform.source_data
	var authored := JSON.new()
	authored.data = original_resource.data.duplicate(true)
	authored.data.records[platform.settings.source_key].fields.appearTerm = 4.625
	platform.source_data = authored
	start(platform)
	check(platform.source_data == authored, "_ready replaced the authored Source Data resource")
	check(platform.recover_after == 4.625, "Runtime ignored the assigned Source Data resource")
	check(original_resource.data.records[platform.settings.source_key].fields.appearTerm != 4.625, "Editing one Source Data resource mutated the original")
	platform.free()


func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func check_preview_restore() -> void:
	var preview: Node2D = Preview.instantiate()
	var platform := preview.get_node("Device") as Node2D
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	author_changes(platform)
	var original := snapshot(platform)
	root.add_child(preview)
	platform.set_physics_process(false)
	var identities := node_ids(platform)
	var camera_transform: Transform3D = platform.camera.transform
	check_snapshot(platform, original, "Preview runtime _ready")
	for iteration in 3:
		root.push_input(key(KEY_V))
		check(preview.inspecting and platform.is_inspecting(), "Preview V did not enter authored-scene inspection")
		var drag := InputEventMouseButton.new()
		drag.button_index = MOUSE_BUTTON_LEFT
		drag.pressed = true
		root.push_input(drag)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(37, -23)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion)
		check(not platform.camera.transform.is_equal_approx(camera_transform), "Preview mouse drag did not orbit the authored scene")
		root.push_input(key(KEY_V if iteration % 2 == 0 else KEY_R))
		check(not preview.inspecting and not platform.is_inspecting(), "Preview V/R failed to leave authored-scene inspection")
		check_snapshot(platform, original, "Preview V/R restoration")
		check_generated_projection(platform, "Preview V/R restoration")
		check(platform.camera.transform.is_equal_approx(camera_transform), "Preview V/R failed to restore generated gameplay camera")
		check(node_ids(platform) == identities, "Preview V/R rebuilt the projected scene")
	preview.free()


func run() -> void:
	var platform := make_unready()
	if not check_serialized_scene(platform):
		platform.free()
		quit(1)
		return
	author_changes(platform)
	var original := snapshot(platform)
	var restored := check_round_trip(platform, original)
	check_authored_material(platform)
	check_snapshot(platform, original, "Direct pre-ready edit")
	check_generated_projection(platform, "Direct pre-ready edit")
	check_idempotence(platform, original)
	check_independence(platform)
	check_snapshot(platform, original, "Inspection/reset after instance-independence checks")
	if restored != null:
		check_idempotence(restored, original)
		restored.free()
	platform.free()
	check_source_layout()
	check_source_resource()
	check_preview_restore()
	for path: String in scratch_paths:
		check(DirAccess.remove_absolute(path) == OK, "Probe could not remove its scratch scene: " + path)
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_SCENE_AUTHORING_PASS checks=", checks)
	quit(1 if failed else 0)
