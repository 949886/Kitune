extends SceneTree
## Verifies the actual imported assets and transforms, not diagnostic frame keys.
## Run after a clean .blend import in a project containing only this device.
const Platform = preload("../DisappearingPlatform3D.tscn")
const Mechanism = preload("../MechanicalModel.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func make_platform() -> Node2D:
	var platform: Node2D = Platform.instantiate()
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	root.add_child(platform)
	platform.set_physics_process(false)
	return platform


func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(all_nodes(child))
	return result


func named(node: Node, wanted: String) -> Node:
	for item: Node in all_nodes(node):
		if String(item.name) == wanted:
			return item
	return null


func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for item: Node in all_nodes(node):
		if item is MeshInstance3D:
			result.append(item)
	return result


func run() -> void:
	var platform := make_platform()
	var other := make_platform()
	check_native_sources(platform)
	check_imported_animation(platform)
	check_gear_geometry(named(platform.mechanism.tread, "GearLeft"))
	check_gear_geometry(named(platform.mechanism.tread, "GearRight"))
	check_palette_materials(platform, other)
	check_hinge_motion(platform, other)
	await check_lifecycle(platform)
	platform.queue_free()
	other.queue_free()
	await process_frame
	if not failed:
		print("DISAPPEARING_PLATFORM_3D_MECHANICAL_PASS checks=", checks)
	quit(1 if failed else 0)


func check_native_sources(platform: Node2D) -> void:
	check(Mechanism.BACKPLATE.resource_path.ends_with("/Backplate.blend"), "Backplate source must be native .blend")
	check(Mechanism.TREAD.resource_path.ends_with("/Tread.blend"), "Tread source must be native .blend")
	check(Mechanism.BACKPLATE != Mechanism.TREAD, "Backplate and Tread must be separate model resources")
	var folder: String = Mechanism.TREAD.resource_path.get_base_dir()
	var blend_files: Array[String] = []
	for filename: String in DirAccess.get_files_at(folder):
		if filename.ends_with(".blend"):
			blend_files.append(filename)
	blend_files.sort()
	check(blend_files == ["Backplate.blend", "Tread.blend"], "Device must contain exactly the two physical native models")
	for path: String in [Mechanism.BACKPLATE.resource_path, Mechanism.TREAD.resource_path]:
		var settings := ConfigFile.new()
		check(settings.load(path + ".import") == OK, "Native model import configuration missing")
		check(settings.get_value("params", "blender/meshes/colors", true) == false, "Imported palette must use materials, not lossy vertex colors")
		check(settings.get_value("params", "blender/materials/export_materials", 0) == 1, "Native palette materials must import")
		check(settings.get_value("params", "meshes/generate_lods", true) == false, "Mechanical source must not receive automatic LODs")
		check(settings.get_value("params", "meshes/force_disable_compression", false), "Lossy mesh compression must be disabled")
	var body_count := 0
	for item: Node in all_nodes(platform.mechanism):
		if String(item.name) == "TreadBody":
			body_count += 1
		check(not String(item.name).begins_with("sharedassets"), "Legacy full-frame pose geometry remains in the assembly")
		check(not item is Sprite3D, "Physical parts cannot be sprite billboards")
	check(body_count == 1, "Assembly must have exactly one persistent physical tread body")
	check(platform.mechanism.hinge == named(platform.mechanism.tread, "TreadHinge"), "Animation must use the imported TreadHinge")
	check(not platform.mechanism.tread.is_ancestor_of(platform.mechanism.backplate), "Stationary backplate is parented to the animated tread")
	for part: MeshInstance3D in meshes(platform.mechanism.tread):
		check(platform.mechanism.hinge.is_ancestor_of(part), "Tread part is not attached to the common hinge: " + str(part.name))
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			check(arrays[Mesh.ARRAY_COLOR] == null or arrays[Mesh.ARRAY_COLOR].is_empty(), "Imported mechanical geometry depends on vertex color")


func check_imported_animation(platform: Node2D) -> void:
	var source: Node = Mechanism.TREAD.instantiate()
	var source_player: AnimationPlayer
	for item: Node in all_nodes(source):
		if item is AnimationPlayer:
			source_player = item
	check(source_player != null, "Tread.blend contains no authored AnimationPlayer")
	var player: AnimationPlayer = platform.mechanism.animation
	check(platform.mechanism.tread.is_ancestor_of(player), "Runtime animation is detached from imported Tread scene")
	check(not player.is_playing(), "Imported animation must not race the platform state clock")
	var fold_count := 0
	for clip_name: StringName in player.get_animation_list():
		if not String(clip_name).contains("Fold"):
			continue
		fold_count += 1
		var clip: Animation = player.get_animation(clip_name)
		check(source_player.has_animation(clip_name), "Runtime Fold clip is absent from native Blender resource")
		check(clip == source_player.get_animation(clip_name), "Runtime replaced authored Fold with a synthesized animation")
		check(clip.length > 0.0, "Authored Fold animation is empty")
		var rotation_tracks := 0
		for track in clip.get_track_count():
			var path: NodePath = clip.track_get_path(track)
			check(String(path).contains("TreadHinge"), "Fold animates a part outside the shared hinge: " + str(path))
			check(clip.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D], "Fold uses a visibility/resource swap instead of a physical transform")
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rotation_tracks += 1
				check(clip.track_get_key_count(track) >= 2, "Fold needs authored rotation endpoints")
		check(rotation_tracks == 1, "Fold must drive one common rotation track")
	check(fold_count == 1, "Expected one native Fold clip")
	source.free()


func check_gear_geometry(gear: MeshInstance3D) -> void:
	check(gear != null and gear.mesh != null, "Missing physical side gear")
	if gear == null or gear.mesh == null:
		return
	var bounds := gear.mesh.get_aabb()
	check(bounds.size.x > 7.7 and bounds.size.x < 8.2, "Gear lacks its authored axial thickness")
	check(bounds.size.y > 41.0 and bounds.size.y <= 42.1 and bounds.size.z > 41.0 and bounds.size.z <= 42.1, "Gear is not a radial wheel in the YZ plane")
	var minimum_radius := INF
	var maximum_radius := 0.0
	var angular_outline: Dictionary = {}
	var axis_crossings := 0
	var bore_wall_triangles := 0
	for surface in gear.mesh.get_surface_count():
		var arrays: Array = gear.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size():
				indices.append(index)
		for point: Vector3 in vertices:
			var radius := Vector2(point.y, point.z).length()
			minimum_radius = minf(minimum_radius, radius)
			maximum_radius = maxf(maximum_radius, radius)
			# Exclude the bore. Keep the outer contour and bevel vertices, then
			# consolidate duplicate front/back angular samples by maximum radius.
			if radius > 9.5:
				var angle := roundi(fposmod(atan2(point.z, point.y), TAU) * 100000.0)
				angular_outline[angle] = maxf(angular_outline.get(angle, 0.0), radius)
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			if covers_axis(Vector2(a.y, a.z), Vector2(b.y, b.z), Vector2(c.y, c.z)):
				axis_crossings += 1
			var radii := Vector3(Vector2(a.y, a.z).length(), Vector2(b.y, b.z).length(), Vector2(c.y, c.z).length())
			if radii.x < 3.8 and radii.y < 3.8 and radii.z < 3.8 and maxf(a.x, maxf(b.x, c.x)) - minf(a.x, minf(b.x, c.x)) > 5.5:
				bore_wall_triangles += 1
	check(minimum_radius > 3.3 and minimum_radius < 3.7, "Gear has no real centered axle opening")
	check(maximum_radius > 20.7 and maximum_radius < 21.2, "Gear tooth crest radius differs from authored solid")
	check(axis_crossings == 0, "A gear face fills the axle opening")
	check(bore_wall_triangles > 0, "Gear bore is missing its solid axial walls")
	var angles: Array = angular_outline.keys()
	angles.sort()
	var peaks := 0
	for index in angles.size():
		var previous: float = angular_outline[angles[(index + angles.size() - 1) % angles.size()]]
		var current: float = angular_outline[angles[index]]
		if current > 19.0 and previous <= 19.0:
			peaks += 1
	check(peaks == 16, "Gear must have 16 real tooth crests, found " + str(peaks))


func covers_axis(a: Vector2, b: Vector2, c: Vector2) -> bool:
	if absf((b - a).cross(c - a)) < 0.0001:
		return false
	var first := (b - a).cross(-a)
	var second := (c - b).cross(-b)
	var third := (a - c).cross(-c)
	return (first >= 0 and second >= 0 and third >= 0) or (first <= 0 and second <= 0 and third <= 0)


func check_hinge_motion(platform: Node2D, other: Node2D) -> void:
	var assembly: Node3D = platform.mechanism
	var hinge: Node3D = assembly.hinge
	var body: MeshInstance3D = named(assembly.tread, "TreadBody")
	var left: MeshInstance3D = named(assembly.tread, "GearLeft")
	var right: MeshInstance3D = named(assembly.tread, "GearRight")
	var parts: Array[MeshInstance3D] = [body, left, right]
	var locals: Array[Transform3D] = []
	var resources: Array[Mesh] = []
	for part: MeshInstance3D in parts:
		locals.append(part.transform)
		resources.append(part.mesh)
	var stationary: Dictionary = {}
	for part: MeshInstance3D in meshes(assembly.backplate):
		stationary[part.get_path()] = part.global_transform
	var other_hinge: Transform3D = other.mechanism.hinge.transform
	var previous_normal := hinge.basis.y
	for step in 101:
		var fraction := float(step) / 100.0
		assembly.set_fold(fraction)
		var expected := Basis(Vector3.RIGHT, fraction * PI * 0.5)
		check(hinge.basis.is_equal_approx(expected), "Imported hinge is not +X 0 to 90 degrees at " + str(fraction))
		check(hinge.position.length() < 0.001, "Fold translated the physical pivot")
		if step > 0:
			check(hinge.basis.y.distance_to(previous_normal) > 0.001, "Intermediate pose repeated instead of moving continuously")
		previous_normal = hinge.basis.y
		for index in parts.size():
			var part := parts[index]
			check(part.transform.is_equal_approx(locals[index]) and part.mesh == resources[index], "Animation changed a child or swapped its mesh")
			check(part.global_basis.is_equal_approx(hinge.global_basis * locals[index].basis), "Gear or tread did not rotate with the common hinge")
		for path: NodePath in stationary:
			check(root.get_node(path).global_transform.is_equal_approx(stationary[path]), "Fold moved stationary backplate geometry")
		check(other.mechanism.hinge.transform == other_hinge, "One instance folded another instance's hinge")
	assembly.set_fold(-2.0)
	check(hinge.basis.is_equal_approx(Basis.IDENTITY), "Fold input did not clamp below zero")
	assembly.set_fold(2.0)
	check(hinge.basis.is_equal_approx(Basis(Vector3.RIGHT, PI * 0.5)), "Fold input did not clamp above one")
	platform.reset()


func sample(platform: Node2D, state_index: int, time: float, blend := 0.0) -> void:
	platform._animation_index = state_index
	platform._animation_time = time
	platform._recover_blend = blend
	platform._sample_animation()


func check_lifecycle(platform: Node2D) -> void:
	var assembly: Node3D = platform.mechanism
	for data: Array in [[1, 1.70, 0.0], [1, 1.75, 0.0], [1, 1.80, 0.25], [1, 1.85, 0.5], [1, 1.90, 0.75], [1, 1.95, 1.0], [2, 0.2, 1.0], [3, 0.05, 0.75], [3, 0.1, 0.5], [3, 0.2, 0.0], [0, 0.0, 0.0]]:
		sample(platform, data[0], data[1])
		check(is_equal_approx(assembly.fold_amount, data[2]), "Physical fold timing differs from the source timeline")
		check(assembly.hinge.basis.is_equal_approx(Basis(Vector3.RIGHT, data[2] * PI * 0.5)), "Timeline updated a value without moving the actual hinge")
	var blend: float = platform.record.states[2].transitions[0].data.m_TransitionDuration
	sample(platform, 3, blend * 0.5, blend)
	check(assembly.fold_amount == 1.0, "Recovery did not hold the source outgoing pose during transition")
	sample(platform, 3, blend - 0.00001, blend)
	var before: Basis = assembly.hinge.basis
	sample(platform, 3, blend + 0.00001, blend)
	check(before.y.distance_to(assembly.hinge.basis.y) < 0.001, "Recovery jumps at the end of the source hold")
	var previous := 1.0
	for step in 101:
		var time := lerpf(blend, 0.2, float(step) / 100.0)
		sample(platform, 3, time, blend)
		check(is_equal_approx(assembly.fold_amount, 1.0 - float(step) / 100.0), "Recovery does not continuously unfold after its source hold")
		check(assembly.fold_amount <= previous + 0.00001, "Recovery hinge reversed direction")
		previous = assembly.fold_amount
	var ids: Dictionary = {}
	for part: MeshInstance3D in meshes(assembly):
		ids[part.get_path()] = [part.get_instance_id(), part.mesh.get_instance_id()]
	var node_total := all_nodes(assembly).size()
	for cycle in 6:
		platform.reset()
		check(platform.activate(), "Mechanical cycle did not start")
		platform.advance(1.75)
		check(is_zero_approx(assembly.fold_amount), "Tread folded before its source interval")
		platform.advance(0.05)
		check(assembly.fold_amount > 0.0 and assembly.fold_amount < 1.0, "Physical tread has no intermediate closing pose")
		platform.advance(0.02)
		await process_frame
		check(platform.state == platform.State.HIDDEN and platform.shape.disabled, "Mechanical revision changed collision disappearance")
		check(assembly.fold_amount > 0.0 and assembly.fold_amount < 1.0, "Collision disappearance replaced the tread with an already folded frame")
		platform.advance(0.13)
		check(is_equal_approx(assembly.fold_amount, 1.0), "Closing animation failed to reach its endpoint")
		platform.advance(1.12)
		await process_frame
		check(platform.state == platform.State.READY and not platform.shape.disabled, "Mechanical revision changed immediate collision recovery")
		check(platform.activate() and platform._pending_active, "Recovery contact no longer queues the next activation")
		platform.advance(0.15)
		check(assembly.fold_amount > 0.0 and assembly.fold_amount < 1.0, "Recovery lacks a visible reversed hinge pose")
		platform.advance(0.15)
		check(platform._animation_index == 1 and not platform._pending_active, "Recovery did not consume queued activation")
		check(all_nodes(assembly).size() == node_total and meshes(assembly).size() == ids.size(), "Repeated cycles multiplied physical parts")
		for path: NodePath in ids:
			var part: MeshInstance3D = root.get_node(path)
			check([part.get_instance_id(), part.mesh.get_instance_id()] == ids[path], "Repeated cycles replaced a physical mesh or node")
	platform.reset()
	platform.settings.time_scale = 0.0
	platform.activate()
	platform.advance(10.0)
	check(assembly.fold_amount == 0.0 and assembly.hinge.basis.is_equal_approx(Basis.IDENTITY), "Paused source clock moved the physical hinge")
	platform.settings.time_scale = 1.0
	platform.reset()


func check_palette_materials(platform: Node2D, other: Node2D) -> void:
	var records: Array = platform.mechanism._surface_materials
	check(not records.is_empty(), "Gameplay palette has no imported solid surfaces")
	var frame := named(platform.mechanism.backplate, "FrameBody") as MeshInstance3D
	var frame_material := frame.get_active_material(0) as StandardMaterial3D
	check(frame_material.albedo_color.r < 0.005 and frame_material.albedo_color.g < 0.005 and frame_material.albedo_color.b < 0.005, "Source black backplate became gray")
	var rail := named(platform.mechanism.tread, "TreadEdgeRails") as MeshInstance3D
	var rail_bounds := rail.mesh.get_aabb()
	check(absf(rail_bounds.size.x - 96.0) < 0.01 and absf(rail_bounds.size.y - 9.0) < 0.01, "READY rail lost its source96x9 profile")
	var silver := false
	var teal := false
	for surface in rail.mesh.get_surface_count():
		var material := rail.get_active_material(surface) as StandardMaterial3D
		var color := material.albedo_color
		silver = silver or (absf(color.r - 169.0/255.0) < 0.002 and absf(color.g - color.r) < 0.002)
		teal = teal or (absf(color.r - 40.0/255.0) < 0.002 and absf(color.g - 79.0/255.0) < 0.002 and absf(color.b - 74.0/255.0) < 0.002)
	check(silver and teal, "Imported rail lost source silver/teal palette bands")
	for entry: Dictionary in records:
		check(entry.palette.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Gameplay color still depends on scene lighting")
		check(entry.palette.albedo_color == entry.lit.albedo_color, "Palette override changed imported source albedo")
		check(entry.palette != entry.lit, "Palette mutated shared native material")
		check(entry.mesh.get_active_material(entry.surface) == entry.palette, "Gameplay solid is using lit material")
	for iteration in 4:
		platform.enter_inspection()
		for entry: Dictionary in records:
			check(entry.mesh.get_active_material(entry.surface) == entry.lit, "Orbit failed to restore native lit surface")
		check(not other.mechanism.inspection_materials, "Orbit changed a second instance palette")
		platform.exit_inspection()
		for entry: Dictionary in records:
			check(entry.mesh.get_active_material(entry.surface) == entry.palette, "Exit failed to restore exact palette resource")
	platform.enter_inspection()
	platform.reset()
	check(not platform.mechanism.inspection_materials, "Reset left gameplay with orbit materials")
