extends SceneTree
## Negative authoring cases emit EXPECTED_CONFIGURATION_ERROR markers followed
## by intentional configuration errors. Generated projection nodes may be built,
## but missing authored references must never be silently replaced or repaired.
const Platform = preload("../DisappearingPlatform3D.tscn")
const ROOT_REFERENCES := ["projection", "solid", "shape", "audio", "settings", "source_data"]
var checks := 0
var expected_errors := 0
var failed := false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("UNEXPECTED_PROBE_FAILURE: " + message)


func make_unready() -> Node2D:
	var platform: Node2D = Platform.instantiate()
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	return platform


func authored_node_ids(node: Node, scene_root: Node = null) -> Array[int]:
	if scene_root == null:
		scene_root = node
	var result: Array[int] = []
	if node == scene_root or node.owner == scene_root:
		result.append(node.get_instance_id())
	for child: Node in node.get_children(true):
		result.append_array(authored_node_ids(child, scene_root))
	return result


func start_invalid(platform: Node2D, context: String) -> void:
	expected_errors += 1
	print("EXPECTED_CONFIGURATION_ERROR ", expected_errors, ": ", context)
	var before := authored_node_ids(platform)
	root.add_child(platform)
	check(not platform._initialized, context + " incorrectly marked initialization complete")
	check(not platform.is_physics_processing(), context + " left physics processing enabled")
	check(authored_node_ids(platform) == before, context + " rebuilt authored nodes instead of reporting the bad reference")
	check(not platform.activate(), context + " allowed activation before initialization")
	platform.advance(10.0)
	platform.reset()
	platform.enter_inspection()
	platform.exit_inspection()
	check(not platform.is_inspecting(), context + " entered inspection before initialization")
	check(platform.state == platform.State.READY and is_zero_approx(platform.elapsed), context + " changed runtime state after failed initialization")


func finish_repaired(platform: Node2D, context: String) -> void:
	var before := authored_node_ids(platform)
	platform._ready()
	check(platform.is_physics_processing(), context + " repair left gameplay physics disabled")
	platform.set_physics_process(false)
	check(platform._initialized, context + " could not initialize after repairing the reference")
	check(authored_node_ids(platform) == before, context + " repair rebuilt authored nodes")
	check(platform.viewport == platform.projection.viewport and platform.camera == platform.projection.camera, context + " repair failed to bind projection runtime references")
	check(platform.mechanism == platform.projection.scene_instance, context + " repair failed to bind the scene instance")
	check(platform.activate(), context + " repair did not restore gameplay activation")
	platform.advance(0.125)
	check(platform.state == platform.State.COUNTDOWN and platform.elapsed > 0.0, context + " repair did not restore gameplay clock")
	platform.reset()
	platform.free()


func check_missing_root_reference(property_name: String) -> void:
	var platform := make_unready()
	var original: Variant = platform.get(property_name)
	platform.set(property_name, null)
	check(not platform._get_configuration_warnings().is_empty(), "Inspector omitted missing-reference warning for " + property_name)
	start_invalid(platform, "missing root " + property_name)
	check(platform.get(property_name) == null, "Invalid authoring silently restored root " + property_name)
	platform.set(property_name, original)
	finish_repaired(platform, "missing root " + property_name)


func check_invalid_source_data() -> void:
	var platform := make_unready()
	var original: JSON = platform.source_data
	platform.source_data = JSON.new()
	platform.source_data.data = ["An array is not a device document"]
	start_invalid(platform, "invalid Source Data document")
	platform.source_data = original
	finish_repaired(platform, "invalid Source Data document")
	platform = make_unready()
	var original_key: String = platform.settings.source_key
	platform.settings.source_key = "missing_source_key"
	start_invalid(platform, "unknown source preset")
	platform.settings.source_key = original_key
	finish_repaired(platform, "unknown source preset")


func check_invalid_projected_scene() -> void:
	var platform := make_unready()
	var original: PackedScene = platform.projection.scene
	platform.projection.scene = null
	start_invalid(platform, "missing projected mechanical scene")
	check(platform.projection.scene == null, "Missing projected scene was silently restored")
	platform.projection.scene = original
	finish_repaired(platform, "missing projected mechanical scene")
	platform = make_unready()
	original = platform.projection.scene
	var unrelated := Node3D.new()
	unrelated.name = "UnrelatedGenericModel"
	var unrelated_scene := PackedScene.new()
	check(unrelated_scene.pack(unrelated) == OK, "Could not prepare unrelated model fixture")
	unrelated.free()
	platform.projection.scene = unrelated_scene
	start_invalid(platform, "projected scene lacks the device mechanical interface")
	check(platform.projection.scene == unrelated_scene, "Device validation replaced the assigned generic model")
	platform.projection.scene = original
	finish_repaired(platform, "projected scene lacks the device mechanical interface")


func check_missing_model_reference(property_name: String) -> void:
	var platform := make_unready()
	check(platform.projection.ensure_built(), "Projection could not build the authored model fixture")
	var mechanism: Node3D = platform.projection.scene_instance
	if mechanism == null:
		platform.free()
		return
	var original: Node3D = mechanism.get(property_name)
	mechanism.set(property_name, null)
	start_invalid(platform, "missing mechanical " + property_name)
	check(not mechanism._initialized, "Failed mechanical setup was marked initialized")
	mechanism.set_fold(0.5)
	check(is_instance_valid(original) and mechanism.is_ancestor_of(original), "Failed setup removed the authored model instance")
	check(platform.projection.scene_instance == mechanism, "Failed setup replaced the generated scene instance")
	mechanism.set(property_name, original)
	finish_repaired(platform, "missing mechanical " + property_name)


func run() -> void:
	for property_name: String in ROOT_REFERENCES:
		check_missing_root_reference(property_name)
	check_invalid_source_data()
	check_invalid_projected_scene()
	for property_name: String in ["backplate", "tread"]:
		check_missing_model_reference(property_name)
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_MISSING_REFERENCE_PASS checks=", checks, " expected_configuration_errors=", expected_errors)
	quit(1 if failed else 0)
