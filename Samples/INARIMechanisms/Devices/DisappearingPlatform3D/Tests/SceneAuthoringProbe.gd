extends SceneTree
## Authoring contract: the packed scene owns its editable nodes and model refs.
## Run after importing the device in a clean project. Scratch scenes are saved
## below user:// and removed; run with XDG_DATA_HOME in a temporary directory.
const Platform = preload("../DisappearingPlatform3D.tscn")
const Preview = preload("../Examples/Preview.tscn")
const CORE_PATHS := {
	"viewport": "Projection3D",
	"model": "Projection3D/SolidGeometry",
	"mechanism": "Projection3D/SolidGeometry/MechanicalAssembly",
	"camera": "Projection3D/Camera3D",
	"display": "Projected3D",
	"solid": "SolidBody2D",
	"shape": "SolidBody2D/CollisionPolygon2D",
	"audio": "ActivationAudio",
}
const ALTERNATE_SOURCE := "level23_7082_0"
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


func check_serialized_scene(platform: Node2D) -> bool:
	var valid := true
	for property_name: String in CORE_PATHS:
		var child: Node = platform.get_node_or_null(CORE_PATHS[property_name])
		check(child != null, "Core node is absent before _ready: " + CORE_PATHS[property_name])
		check(is_exported(platform, property_name, TYPE_OBJECT), "Core node reference is not an exported object: " + property_name)
		check(platform.get(property_name) == child and child != null, "Serialized node reference is not resolved before _ready: " + property_name)
		if child != null:
			check(child.owner == platform, "Core node is not owned by its editable packed scene: " + property_name)
		else:
			valid = false
	if not valid:
		return false
	check(platform.get_node_or_null("Projection3D/MechanicalKeyLight") is DirectionalLight3D, "Mechanical light is not serialized")
	for property_name: String in ["backplate", "tread"]:
		var part: Node3D = platform.mechanism.get(property_name)
		check(is_exported(platform.mechanism, property_name, TYPE_OBJECT), "Imported model reference is not editor-visible: " + property_name)
		check(part != null, "Imported model is missing before _ready: " + property_name)
		if part == null:
			valid = false
			continue
		check(part.get_parent() == platform.mechanism, "Imported model was not authored under MechanicalAssembly")
		var filename := "Backplate.blend" if property_name == "backplate" else "Tread.blend"
		check(part.scene_file_path.ends_with("/" + filename), "Model does not retain a native .blend scene reference: " + property_name)
	check(is_exported(platform, "source_data", TYPE_OBJECT) and platform.source_data is JSON, "Source data must be an exported JSON resource")
	check(is_exported(platform, "auto_apply_source_layout", TYPE_BOOL), "Automatic preset-layout opt-out is not exported")
	check(is_exported(platform, "layout_source_key", TYPE_STRING), "Authored source-layout key is not exported")
	check(platform.auto_apply_source_layout and platform.layout_source_key == platform.settings.source_key, "Default scene would overwrite its authored layout on _ready")
	return valid


func author_changes(platform: Node2D) -> void:
	platform.viewport.size = Vector2i(311, 227)
	platform.viewport.transparent_bg = false
	platform.camera.transform = Transform3D(Basis.from_euler(Vector3(0.03, -0.07, 0.01)), Vector3(17, -9, 480))
	platform.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	platform.camera.keep_aspect = Camera3D.KEEP_WIDTH
	platform.camera.size = 187.35
	platform.camera.fov = 51.25
	platform.camera.near = 0.25
	platform.camera.far = 777.0
	platform.camera.h_offset = 2.75
	platform.camera.v_offset = -1.25
	platform.camera.environment = platform.camera.environment.duplicate()
	platform.camera.environment.resource_local_to_scene = true
	platform.camera.environment.ambient_light_color = Color(0.17, 0.39, 0.58, 1)
	platform.camera.environment.ambient_light_energy = 0.37
	platform.model.transform = Transform3D(Basis.from_euler(Vector3(0.02, 0.04, -0.03)).scaled(Vector3(0.95, 1.1, 1.05)), Vector3(3, -7, 2))
	platform.mechanism.position = Vector3(5.25, -3.125, 1.5)
	platform.mechanism.rotation = Vector3(0.0, 0.02, 0.01)
	platform.mechanism.backplate.position = Vector3(0.5, -0.75, 1.25)
	platform.mechanism.tread.position = Vector3(-0.25, 0.5, -0.75)
	platform.display.position = Vector2(-114.75, -67.5)
	platform.display.offset = Vector2(3, -2)
	platform.display.flip_h = true
	platform.display.modulate = Color(0.9, 0.8, 0.7, 0.6)
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
	var light := platform.get_node("Projection3D/MechanicalKeyLight") as DirectionalLight3D
	light.rotation_degrees = Vector3(-31, -17, 6)
	light.light_energy = 0.625
	light.light_color = Color(0.73, 0.81, 0.95, 1)


func snapshot(platform: Node2D) -> Dictionary:
	var light := platform.get_node("Projection3D/MechanicalKeyLight") as DirectionalLight3D
	return {
		"viewport": [platform.viewport.size, platform.viewport.transparent_bg],
		"camera": [platform.camera.transform, platform.camera.projection, platform.camera.keep_aspect, platform.camera.size, platform.camera.fov, platform.camera.near, platform.camera.far, platform.camera.h_offset, platform.camera.v_offset],
		"environment": [platform.camera.environment.ambient_light_color, platform.camera.environment.ambient_light_energy],
		"model": [platform.model.transform, platform.mechanism.transform, platform.mechanism.backplate.transform, platform.mechanism.tread.transform],
		"display": [platform.display.position, platform.display.offset, platform.display.flip_h, platform.display.modulate],
		"solid": [platform.solid.transform, platform.solid.collision_layer, platform.solid.collision_mask],
		"shape": [platform.shape.transform, platform.shape.polygon.duplicate()],
		"audio": [platform.audio.stream.get_class(), platform.audio.stream.data.duplicate(), platform.audio.stream.mix_rate, platform.audio.volume_db, platform.audio.pitch_scale, platform.audio.max_polyphony],
		"light": [light.transform, light.light_energy, light.light_color],
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


func node_ids(platform: Node2D) -> Array[int]:
	var result: Array[int] = []
	for node: Node in all_nodes(platform):
		result.append(node.get_instance_id())
	return result


func check_idempotence(platform: Node2D, original: Dictionary) -> void:
	var identities := node_ids(platform)
	var camera_environment: Environment = platform.camera.environment
	var audio_stream: AudioStream = platform.audio.stream
	var source_data: JSON = platform.source_data
	var palette_ids: Array[int] = []
	for entry: Dictionary in platform.mechanism._surface_materials:
		palette_ids.append(entry.palette.get_instance_id())
	var alarm_material: Material = platform.mechanism.alarm.material_override
	check(platform.activate(), "Authored scene did not activate before idempotence checks")
	platform.advance(0.125)
	var clocks: Array = [platform.state, platform.elapsed, platform._animation_index, platform._animation_time]
	for iteration in 4:
		check(platform.mechanism.setup(), "Repeated mechanical setup failed")
		platform._ready()
		platform.set_physics_process(false)
		check_snapshot(platform, original, "Repeated setup/_ready")
		check([platform.state, platform.elapsed, platform._animation_index, platform._animation_time] == clocks, "Repeated _ready restarted active gameplay state or clocks")
		check(node_ids(platform) == identities, "Repeated setup created, replaced, or reordered scene nodes")
		check(platform.camera.environment == camera_environment and platform.audio.stream == audio_stream and platform.source_data == source_data, "Repeated setup replaced an authored resource")
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
	check(platform.display.texture != other.display.texture, "Instances share the serialized ViewportTexture resource")
	check(platform.display.texture.get_size() == Vector2(platform.viewport.size) and other.display.texture.get_size() == Vector2(other.viewport.size), "A serialized ViewportTexture targets the wrong instance")
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
	var part := named(platform.mechanism.backplate, "FrameBody") as MeshInstance3D
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
	start(platform)
	check(part.mesh == mesh_resource and part.transform == transform_before, "Setup replaced or transformed authored mesh geometry")
	check(part.get_active_material(0).albedo_color == material.albedo_color, "Gameplay palette discarded authored surface color")
	platform.enter_inspection()
	check(part.get_active_material(0) == material, "Inspection does not restore the authored surface override resource")
	platform.exit_inspection()
	check(material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and is_equal_approx(material.metallic, 0.21), "Runtime modified the source material instead of an instance override")


func check_round_trip(platform: Node2D, original: Dictionary) -> Node2D:
	var packed := PackedScene.new()
	check(packed.pack(platform) == OK, "Edited scene could not be packed before _ready")
	var path := "user://scene_authoring_probe_%s.tscn" % Time.get_ticks_usec()
	var saved := ResourceSaver.save(packed, path)
	check(saved == OK, "Edited packed scene could not be saved")
	if saved != OK:
		return null
	var reloaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(reloaded != null, "Edited packed scene could not be reloaded")
	if reloaded == null:
		DirAccess.remove_absolute(path)
		return null
	var restored := reloaded.instantiate() as Node2D
	check_snapshot(restored, original, "Packed scene save/reload before _ready")
	var before := node_ids(restored)
	start(restored)
	check_snapshot(restored, original, "Packed scene save/reload runtime _ready")
	check(node_ids(restored) == before, "_ready created or replaced nodes after packed-scene reload")
	check(restored._initialized, "Reloaded authored scene did not initialize")
	check(DirAccess.remove_absolute(path) == OK, "Probe could not remove its scratch packed scene")
	return restored


func source_layout_snapshot(platform: Node2D) -> Array:
	return [platform.viewport.size, platform.camera.position, platform.camera.size, platform.display.position, platform.mechanism.position, platform.shape.polygon.duplicate()]


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
	manual.apply_source_layout()
	check(equivalent(source_layout_snapshot(manual), expected), "Explicit source layout did not match the alternate preset")
	check(manual.layout_source_key == ALTERNATE_SOURCE, "Explicit source layout did not record the source key")
	check(manual.model.transform.is_equal_approx(original.model[0]), "Explicit source layout unexpectedly reset the host model transform")
	check(manual.audio.volume_db == original.audio[3], "Explicit source layout unexpectedly reset audio properties")
	manual.camera.position += Vector3(7, 8, 0)
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
		check(not platform.camera.transform.is_equal_approx(original.camera[0]), "Preview mouse drag did not orbit the authored scene")
		root.push_input(key(KEY_V if iteration % 2 == 0 else KEY_R))
		check(not preview.inspecting and not platform.is_inspecting(), "Preview V/R failed to leave authored-scene inspection")
		check_snapshot(platform, original, "Preview V/R restoration")
		check(node_ids(platform) == identities, "Preview V/R rebuilt the authored scene")
	preview.free()


func run() -> void:
	var platform := make_unready()
	if not check_serialized_scene(platform):
		platform.free()
		quit(1)
		return
	author_changes(platform)
	var original := snapshot(platform)
	var before := node_ids(platform)
	var restored := check_round_trip(platform, original)
	check_authored_material(platform)
	check_snapshot(platform, original, "Direct pre-ready edit")
	check(node_ids(platform) == before, "Direct _ready created or replaced authored scene nodes")
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
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_SCENE_AUTHORING_PASS checks=", checks)
	quit(1 if failed else 0)
