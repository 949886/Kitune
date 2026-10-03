extends SceneTree
## Run after importing an empty project containing ONLY the device directory:
## godot --headless --path <project> --script res://<device>/Tests/StandaloneProbe.gd
## When the legacy sibling is present, its runtime is also compared directly.
const Platform = preload("../DisappearingPlatform3D.tscn")
var _checks := 0
var _failed := false
var _activation_count := 0


class ContactActor extends CharacterBody2D:
	var gravity := Vector2.ZERO
	var contacts: Array[Vector2] = []

	func _physics_process(delta: float) -> void:
		velocity += gravity * delta
		move_and_slide()
		for index in get_slide_collision_count():
			contacts.append(get_slide_collision(index).get_normal())


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error(message)
		quit(1)


func frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func make_platform(parent: Node = null, source_key := "") -> Node2D:
	if parent == null:
		parent = root
	var platform: Node2D = Platform.instantiate()
	platform.settings = platform.settings.duplicate()
	platform.settings.sound_enabled = false
	if not source_key.is_empty():
		platform.settings.source_key = source_key
	parent.add_child(platform)
	platform.set_physics_process(false)
	return platform


func run() -> void:
	var platform := make_platform()
	await check_timing_and_reset(platform)
	await check_geometry_and_isolation(platform)
	await check_presets()
	await compare_legacy(platform)
	platform.queue_free()
	await frames(2)
	await check_transformed_contacts()
	if not _failed:
		print("STANDALONE_DISAPPEARING_PLATFORM_3D_PASS checks=", _checks)
	quit(1 if _failed else 0)


func check_timing_and_reset(platform: Node2D) -> void:
	check(is_equal_approx(platform.disappear_after, 109.0 / 60.0), "Source disappear timing changed")
	check(is_equal_approx(platform.recover_after, 1.25), "Source recover timing changed")
	check(platform.visuals.size() == 4, "All four source visual layers are required")
	var emission = platform.visuals[platform.record.states[0].alpha.go]
	check(emission.modulate.a == 0.0, "Idle emission must be off")
	platform.activated.connect(func(): _activation_count += 1)
	check(platform.activate(), "Initial activation must succeed")
	platform.advance(0.22)
	check(emission.modulate.a == 1.0, "First source alarm flash missing")
	var elapsed: float = platform.elapsed
	var animation_time: float = platform._animation_time
	check(not platform.activate(), "Repeated contact must not reactivate countdown")
	check(_activation_count == 1 and platform.elapsed == elapsed and platform._animation_time == animation_time, "Repeated activation restarted a clock or signal")
	platform.advance(0.20)
	check(emission.modulate.a == 0.0, "Source alarm flash must switch off")
	platform.advance(1.4)
	await process_frame
	check(platform.state == platform.State.HIDDEN and platform.shape.disabled, "Countdown must remove collision")
	check(not platform.activate(), "Hidden platforms cannot activate")
	platform.advance(1.24)
	check(platform.state == platform.State.HIDDEN, "Recovery happened early")
	platform.advance(0.01)
	await process_frame
	check(platform.state == platform.State.READY and not platform.shape.disabled, "Recovery must restore collision immediately")
	check(platform._animation_index == 3, "Recovery must start the opening animation")
	check(platform.activate() and platform._pending_active, "Contact during recovery must queue Active")
	check(platform._animation_index == 3, "Queued activation must not interrupt Recover")
	check(not platform.activate(), "Queued activation cannot restart countdown")
	platform.advance(0.3)
	check(platform._animation_index == 1 and not platform._pending_active, "Recovery must consume the queued Active request")
	platform.reset()
	await process_frame
	check(platform.state == platform.State.READY and platform._animation_index == 0 and not platform.shape.disabled, "Reset must restore idle and collision")
	check(platform.elapsed == 0.0 and not platform._pending_active and platform._recover_blend == 0.0 and not platform.audio.playing, "Reset left timers, queued work or audio active")
	check(emission.modulate.a == 0.0, "Reset must clear alarm emission")
	platform.settings.time_scale = 0.0
	platform.activate()
	platform.advance(10.0)
	check(platform.elapsed == 0.0 and platform._animation_time == 0.0 and platform.state == platform.State.COUNTDOWN, "Zero time scale must pause behavior and animation")
	platform.settings.time_scale = 1.0
	platform.advance(-10.0)
	check(platform.elapsed == 0.0 and platform._animation_time == 0.0, "Negative delta must not reverse either clock")
	for rate in [30, 60, 120]:
		for speed in [0.5, 1.0, 2.0]:
			platform.reset()
			platform.settings.time_scale = speed
			platform.activate()
			var before: int = ceili(platform.disappear_after * rate / speed) - 1
			for _frame in before:
				platform.advance(1.0 / rate)
			check(platform.state == platform.State.COUNTDOWN, "Disappearance happened before its quantized tick")
			platform.advance(1.0 / rate)
			check(platform.state == platform.State.HIDDEN, "Disappearance missed its quantized tick")
			before = ceili(platform.recover_after * rate / speed) - 1
			for _frame in before:
				platform.advance(1.0 / rate)
			check(platform.state == platform.State.HIDDEN, "Recovery happened before its quantized tick")
			platform.advance(1.0 / rate)
			check(platform.state == platform.State.READY, "Recovery missed its quantized tick")
	platform.settings.time_scale = 1.0
	# Reset must cancel work from both hidden and recovery-queued states.
	platform.reset()
	platform.activate()
	platform.advance(platform.disappear_after)
	platform.reset()
	await process_frame
	check(not platform.shape.disabled and platform.state == platform.State.READY, "Reset failed while hidden")
	platform.activate()
	platform.advance(platform.disappear_after)
	platform.advance(platform.recover_after)
	platform.activate()
	platform.reset()
	platform.advance(0.3)
	await process_frame
	check(platform._animation_index == 0 and not platform._pending_active and not platform.shape.disabled, "Reset allowed queued recovery activation to return")


func check_geometry_and_isolation(platform: Node2D) -> void:
	check(platform.viewport is SubViewport and platform.viewport.transparent_bg, "3D output must use a transparent SubViewport")
	check(platform.viewport.own_world_3d, "Each viewport must own its isolated 3D world")
	check(platform.camera is Camera3D and platform.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Pixel-plane output requires an orthographic camera")
	check(platform.display is Sprite2D and platform.display.texture is ViewportTexture, "Final 2D output must be the viewport texture")
	var second := make_platform()
	check(platform.viewport.find_world_3d() != second.viewport.find_world_3d(), "Instances share a 3D world")
	check(platform.viewport.get_texture() != second.viewport.get_texture(), "Instances share their rendered texture")
	platform.activate()
	platform.advance(0.22)
	var other_emission = second.visuals[second.record.states[0].alpha.go]
	check(second.state == second.State.READY and other_emission.modulate.a == 0.0, "One instance changed another's state or material alpha")
	for go in platform.visuals:
		var visual = platform.visuals[go]
		check(visual is MeshInstance3D, "Source artwork must be actual MeshInstance3D geometry")
		check(visual.material_override != second.visuals[go].material_override, "Mutable materials must be per-instance")
		check_mesh(visual)
	check_only_viewport_sprite(platform, platform.display)
	# Exercise every source key, including the 13 animated poses and 3 overlays.
	check(platform._library.size() == 16, "The complete source geometry library must contain 16 keys")
	var target = platform.visuals[platform.record.states[0].track.go]
	var mesh_ids: Dictionary = {}
	for key: String in platform._library:
		platform._set_sprite(target, key)
		check(target.current_key == key, "Visual did not retain the selected source frame key")
		check_mesh(target)
		mesh_ids[target.mesh.get_instance_id()] = true
	check(mesh_ids.size() == 16, "All 16 source artworks need their own geometry")
	platform.reset()
	second.queue_free()
	await process_frame


func check_mesh(visual: MeshInstance3D) -> void:
	check(visual.mesh != null and visual.mesh.get_surface_count() > 0, "Missing 3D geometry")
	check(visual.mesh.get_aabb().size.z >= 1.99, "Artwork is a flat textured plane rather than a solid extrusion")
	var has_side_faces := false
	for surface in visual.mesh.get_surface_count():
		var arrays: Array = visual.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(vertices.size() >= 8 and indices.size() >= 12, "Extruded geometry needs vertices and triangle faces")
		# Unshaded materials need no stored normals. Inspect the actual triangles.
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			var normal := (b - a).cross(c - a).normalized()
			if normal.length_squared() > 0.5 and absf(normal.z) < 0.5:
				has_side_faces = true
				break
		check_material(visual.mesh.surface_get_material(surface))
	check(has_side_faces, "Geometry has no thickness-defining side faces")
	check_material(visual.material_override)


func check_material(material: Material) -> void:
	if material == null:
		return
	check(material is BaseMaterial3D, "Geometry materials must expose their non-textured color source")
	if material is BaseMaterial3D:
		for property: Dictionary in material.get_property_list():
			if property.name.ends_with("_texture"):
				check(not material.get(property.name) is Texture, "Geometry material uses a sprite/image texture: " + property.name)


func check_only_viewport_sprite(node: Node, display: Sprite2D) -> void:
	check(not node is Sprite3D, "Sprite3D billboards cannot replace extruded artwork")
	if node is Sprite2D:
		check(node == display and node.texture is ViewportTexture, "Only the final viewport-output Sprite2D is allowed")
	for child in node.get_children():
		check_only_viewport_sprite(child, display)


func check_presets() -> void:
	var folder: String = Platform.resource_path.get_base_dir()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/device.json"))
	check(data.records.size() == 14, "All 14 source presets must be portable")
	for key: String in data.records:
		var platform := make_platform(root, key)
		check(platform.shape.polygon.size() == data.records[key].polygon.size(), "Preset collision polygon size changed")
		for index in platform.shape.polygon.size():
			var point: Array = data.records[key].polygon[index]
			check(platform.shape.polygon[index].is_equal_approx(Vector2(point[0], point[1])), "Preset collision point changed")
		check(platform.solid.collision_layer == 1 and platform.solid.collision_mask == 0, "Original 2D collision filtering changed")
		platform.queue_free()
		await process_frame


func compare_legacy(platform: Node2D) -> void:
	var path: String = Platform.resource_path.get_base_dir().get_base_dir() + "/DisappearingPlatform/DisappearingPlatform.tscn"
	if not ResourceLoader.exists(path):
		print("LEGACY_COMPARISON_SKIPPED (standalone copy; source-data assertions remain active)")
		return
	var scene: PackedScene = load(path)
	var legacy: Node2D = scene.instantiate()
	legacy.settings = legacy.settings.duplicate()
	legacy.settings.sound_enabled = false
	root.add_child(legacy)
	legacy.set_physics_process(false)
	var legacy_events: Array = []
	var actual_events: Array = []
	legacy.state_changed.connect(func(value): legacy_events.append(value))
	var collect_actual := func(value): actual_events.append(value)
	platform.state_changed.connect(collect_actual)
	for speed in [0.0, 0.5, 1.0, 2.0]:
		platform.settings.time_scale = speed
		legacy.settings.time_scale = speed
		platform.reset()
		legacy.reset()
		platform.activate()
		legacy.activate()
		for tick in 960:
			if tick % 5 == 0:
				check(platform.activate() == legacy.activate(), "Activation acceptance differs from legacy")
			platform.advance(1.0 / 120.0)
			legacy.advance(1.0 / 120.0)
			check(platform.state == legacy.state and platform._animation_index == legacy._animation_index, "Runtime state differs from legacy")
			check(is_equal_approx(platform.elapsed, legacy.elapsed) and is_equal_approx(platform._animation_time, legacy._animation_time), "Animation/state clock differs from legacy")
			check(platform._pending_active == legacy._pending_active, "Recover queue differs from legacy")
			var alpha_go = platform.record.states[0].alpha.go
			check(is_equal_approx(platform.visuals[alpha_go].modulate.a, legacy.visuals[alpha_go].modulate.a), "Emission curve differs from legacy")
			var go = platform.record.states[0].track.go
			var expected_key: String = legacy.visuals[go].texture.resource_path.get_file().get_basename()
			check(platform.visuals[go].current_key == expected_key, "Frame selection differs from legacy")
		await process_frame
		check(platform.shape.disabled == legacy.shape.disabled, "Deferred collision state differs from legacy")
		check(actual_events == legacy_events, "State-change signal sequence differs from legacy")
	platform.state_changed.disconnect(collect_actual)
	platform.settings.time_scale = 1.0
	platform.reset()
	legacy.queue_free()
	await process_frame
	print("LEGACY_TIMING_AND_ANIMATION_EQUIVALENCE_PASS")


func check_transformed_contacts() -> void:
	var parent := Node2D.new()
	parent.position = Vector2(310, 220)
	parent.rotation = 0.2
	parent.scale = Vector2.ONE * 1.5
	root.add_child(parent)
	var platform := make_platform(parent)
	await frames(2)
	var query := PhysicsRayQueryParameters2D.create(parent.to_global(Vector2(0, -30)), parent.to_global(Vector2(0, 30)), 1)
	var hit := root.world_2d.direct_space_state.intersect_ray(query)
	check(hit.get("collider") == platform.solid, "Transformed platform lost its 2D collision")
	check(hit.position.distance_to(parent.to_global(Vector2.ZERO)) < 0.01, "Transformed collision surface is displaced from the source origin")
	var actor := ContactActor.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.up_direction = -parent.global_transform.y.normalized()
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 12)
	collider.shape = rectangle
	actor.add_child(collider)
	actor.position = Vector2(0, 50)
	parent.add_child(actor)
	platform.bind_actor(actor)
	platform.set_physics_process(true)
	actor.velocity = -parent.global_transform.y.normalized() * 360.0
	await frames(20)
	check(actor.contacts.any(func(normal): return normal.dot(actor.up_direction) < -0.99), "Underside setup must produce a real slide collision")
	check(platform.state == platform.State.READY, "Underside contact incorrectly activated the platform")
	actor.contacts.clear()
	actor.position = Vector2(70, 8)
	actor.velocity = -parent.global_transform.x.normalized() * 240.0
	await frames(20)
	check(actor.contacts.any(func(normal): return absf(normal.dot(actor.up_direction)) < 0.01), "Side setup must produce a real slide collision")
	check(platform.state == platform.State.READY, "Side contact incorrectly activated the platform")
	platform.bind_actor(actor, func(): return false)
	actor.position = Vector2(0, -45)
	actor.velocity = Vector2.ZERO
	actor.gravity = parent.global_transform.y.normalized() * 900.0
	await frames(40)
	check(actor.is_on_floor() and platform.state == platform.State.READY, "Dead predicate must suppress a genuine top contact")
	platform.bind_actor(actor)
	await frames(2)
	check(platform.state == platform.State.COUNTDOWN, "Rotated/scaled top slide contact did not activate")
	actor.position = Vector2(180, -45)
	actor.velocity = Vector2.ZERO
	var hidden := false
	for _frame in 120:
		await frames(1)
		if platform.state == platform.State.HIDDEN:
			hidden = true
			break
	check(hidden and platform.shape.disabled, "Leaving the platform incorrectly cancelled countdown")
	# A second real landing stays on the platform until it disappears; the actor
	# must actually fall through the disabled shape, not just observe a flag.
	platform.reset()
	actor.position = Vector2(0, -45)
	actor.velocity = Vector2.ZERO
	await frames(40)
	check(actor.is_on_floor() and platform.state == platform.State.COUNTDOWN, "Second landing failed to start a fresh cycle")
	for _frame in 120:
		await frames(1)
		if platform.state == platform.State.HIDDEN:
			break
	await frames(20)
	check(actor.position.y > 16.0 and not actor.is_on_floor(), "Disabled platform did not let the actor fall")
	actor.queue_free()
	await frames(2)
	check(platform._actor.get_ref() == null, "Actor binding must not retain a freed room actor")
	parent.queue_free()
	await frames(2)
