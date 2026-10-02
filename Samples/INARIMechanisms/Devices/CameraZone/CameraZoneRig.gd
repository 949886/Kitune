extends Node
## Optional renderer for a planar host. Uses the original framing/depth damper;
## zone commands also work with a host's own 2D/3D camera without this adapter.
const NativeRig = preload("../../Core/Native/Runtime/InariCameraRig.gd")
const Location = preload("../../PackageLocation.gd")
var controller: Node
var renderer: Node
var marker: Node2D
var owns_camera := true


func bind_controller(coordinator: Node, origin_offset := Vector2.ZERO) -> void:
	assert(renderer == null, "Recreate the camera adapter when replacing its host")
	controller = coordinator
	var folder: String = (Location as Script).resource_path.get_base_dir()
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/CameraZone/camera.json"))
	renderer = NativeRig.new()
	add_child(renderer)
	renderer.configure_host(controller.player, profile, controller.pixels_per_unit, origin_offset)
	marker = Node2D.new()
	add_child(marker)
	process_priority = 250


func _process(_delta: float) -> void:
	if not owns_camera or not is_instance_valid(controller) or not is_instance_valid(controller.player): return
	var state: Dictionary = controller.target_state()
	marker.global_position = state.position
	renderer.target = marker
	renderer.target_offset = Vector2.ZERO
	renderer.target_depth = state.depth
	renderer.source.damping[2] = state.z_damping
	renderer.framing.m_UnlimitedSoftZone = state.unlimited_soft_zone
