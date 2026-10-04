extends SceneTree
## Negative authoring cases emit EXPECTED_CONFIGURATION_ERROR markers followed
## by one intentional push_error per case. No script errors, crashes, rebuilding,
## or invalid accesses should occur; repaired references must initialize cleanly.
const Platform = preload("../DisappearingPlatform3D.tscn")
const ROOT_REFERENCES := ["viewport", "camera", "display", "model", "mechanism", "solid", "shape", "audio", "settings", "source_data"]
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


func node_ids(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	for child: Node in node.get_children():
		result.append_array(node_ids(child))
	return result


func start_invalid(platform: Node2D, context: String) -> void:
	expected_errors += 1
	print("EXPECTED_CONFIGURATION_ERROR ", expected_errors, ": ", context)
	var before := node_ids(platform)
	root.add_child(platform)
	check(not platform._initialized, context + " incorrectly marked initialization complete")
	check(not platform.is_physics_processing(), context + " left physics processing enabled")
	check(node_ids(platform) == before, context + " rebuilt scene nodes instead of reporting the bad reference")
	check(not platform.activate(), context + " allowed activation before initialization")
	platform.advance(10.0)
	platform.reset()
	platform.enter_inspection()
	platform.exit_inspection()
	check(not platform.is_inspecting(), context + " entered inspection before initialization")
	check(platform.state == platform.State.READY and is_zero_approx(platform.elapsed), context + " changed runtime state after failed initialization")


func finish_repaired(platform: Node2D, context: String) -> void:
	var before := node_ids(platform)
	platform._ready()
	check(platform.is_physics_processing(), context + " repair left gameplay physics disabled")
	platform.set_physics_process(false)
	check(platform._initialized, context + " could not initialize after repairing the reference")
	check(node_ids(platform) == before, context + " repair rebuilt the authored scene")
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


func check_missing_model_reference(property_name: String) -> void:
	var platform := make_unready()
	var original: Node3D = platform.mechanism.get(property_name)
	platform.mechanism.set(property_name, null)
	start_invalid(platform, "missing mechanical " + property_name)
	check(not platform.mechanism._initialized, "Failed mechanical setup was marked initialized")
	platform.mechanism.set_fold(0.5)
	check(node_ids(platform).has(original.get_instance_id()), "Failed setup removed the authored model instance")
	platform.mechanism.set(property_name, original)
	finish_repaired(platform, "missing mechanical " + property_name)


func run() -> void:
	for property_name: String in ROOT_REFERENCES:
		check_missing_root_reference(property_name)
	check_invalid_source_data()
	for property_name: String in ["backplate", "tread"]:
		check_missing_model_reference(property_name)
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_MISSING_REFERENCE_PASS checks=", checks, " expected_configuration_errors=", expected_errors)
	quit(1 if failed else 0)
