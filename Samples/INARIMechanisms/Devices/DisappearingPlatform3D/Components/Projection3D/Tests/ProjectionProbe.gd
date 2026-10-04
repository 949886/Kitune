extends SceneTree
## Generic, dependency-free Projection3D lifecycle regression.
## Copy only the Projection3D directory into an empty Godot project, then run:
## godot --headless --path <project> --script res://Projection3D/Tests/ProjectionProbe.gd
## Add --editor for the same assertions with real Engine.is_editor_hint() == true.
## Invalid Node2D scene tests deliberately produce clear configuration errors.
const ProjectionScript = preload("../Projection3D.gd")
const ProjectionScene = preload("../Projection3D.tscn")
const SCRATCH_PATH := "user://projection3d_lifecycle_probe.tscn"
var checks := 0
var failed := false
var rebuilt_count := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("ProjectionProbe: " + message)


func frames(count := 2) -> void:
	for _index in count:
		await process_frame


func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children(true):
		result.append_array(all_nodes(child))
	return result


func identities(node: Node) -> Array[int]:
	var result: Array[int] = []
	for child: Node in all_nodes(node):
		result.append(child.get_instance_id())
	return result


func descendants_gone(ids: Array[int], context: String) -> void:
	for identity: int in ids:
		check(not is_instance_id_valid(identity), context + " retained old node " + str(identity))


func generated_ids(projection: Node) -> Array[int]:
	var result := identities(projection)
	result.remove_at(0)
	return result


func is_exported(object: Object, property_name: String, expected_type: int) -> bool:
	for entry: Dictionary in object.get_property_list():
		if entry.name == property_name:
			return entry.type == expected_type and (entry.usage & PROPERTY_USAGE_EDITOR) != 0 and (entry.usage & PROPERTY_USAGE_STORAGE) != 0
	return false


func make_scene(content_name: String, valid := true) -> PackedScene:
	var content: Node = Node3D.new() if valid else Node2D.new()
	content.name = content_name
	if content is Node3D:
		content.position = Vector3(3.0, 4.0, 5.0)
	var child := Node3D.new()
	child.name = "NestedContent"
	content.add_child(child)
	child.owner = content
	child.unique_name_in_owner = true
	var mesh := MeshInstance3D.new()
	mesh.name = "ContentMesh"
	mesh.mesh = BoxMesh.new()
	child.add_child(mesh)
	mesh.owner = content
	var authored_camera := Camera3D.new()
	authored_camera.name = "ContentCamera"
	authored_camera.current = true
	content.add_child(authored_camera)
	authored_camera.owner = content
	var packed := PackedScene.new()
	check(packed.pack(content) == OK, "Synthetic content scene could not be packed")
	content.free()
	var baseline := packed.instantiate()
	check(baseline.get_node_or_null("%NestedContent") != null, "Synthetic content lost its native unique-name reference before injection")
	baseline.free()
	return packed


func check_pipeline(projection: Node2D, context: String) -> bool:
	var viewport: SubViewport = projection.get("viewport")
	var camera: Camera3D = projection.get("camera")
	var sprite: Sprite2D = projection.get("sprite")
	var container: Node3D = projection.get("scene_container")
	check(is_instance_valid(viewport), context + " has no viewport")
	check(is_instance_valid(camera), context + " has no camera")
	check(is_instance_valid(sprite), context + " has no sprite")
	check(is_instance_valid(container), context + " has no scene container")
	if viewport == null or camera == null or sprite == null or container == null:
		return false
	check(viewport.get_parent() == projection and sprite.get_parent() == projection, context + " generated output nodes have wrong parents")
	check(camera.get_parent() == viewport and container.get_parent() == viewport, context + " 3D nodes are outside their viewport")
	check(viewport.own_world_3d, context + " must own its 3D world")
	check(viewport.transparent_bg, context + " viewport must be transparent")
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, context + " camera must be orthographic")
	check(camera.current, context + " an injected content camera took control of the viewport")
	check(sprite.texture is ViewportTexture and sprite.texture == viewport.get_texture(), context + " sprite does not display its own viewport")
	check(projection.get_child_count() == 0, context + " generated children are exposed in normal child enumeration")
	check(camera.environment != null, context + " camera has no generated environment")
	var lights := viewport.find_children("*", "Light3D", true, false)
	check(lights.size() == 1, context + " must contain exactly one generated light")
	var content: Node3D = projection.get("scene_instance")
	for node: Node in all_nodes(projection):
		if node == projection or (content != null and content.is_ancestor_of(node)):
			continue
		check(node.owner == null, context + " generated infrastructure unexpectedly has a serialization owner: " + str(node.name))
	if content != null:
		var unique_child := content.get_node_or_null("%NestedContent")
		check(unique_child != null and unique_child == content.get_node_or_null("NestedContent"), context + " broke native scene unique-name resolution")
		if unique_child != null:
			check(unique_child.owner == content, context + " lost the injected descendant's native serialization owner")
	return true


func check_settings(projection: Node2D, context: String) -> void:
	var viewport: SubViewport = projection.get("viewport")
	var camera: Camera3D = projection.get("camera")
	var sprite: Sprite2D = projection.get("sprite")
	var container: Node3D = projection.get("scene_container")
	check(viewport.size == projection.get("viewport_size"), context + " viewport size did not apply")
	check(is_equal_approx(camera.size, projection.get("camera_size")), context + " camera size did not apply")
	check(camera.position.is_equal_approx(projection.get("camera_position")), context + " camera position did not apply")
	check(sprite.position.is_equal_approx(projection.get("sprite_position")), context + " sprite position did not apply")
	check(container.transform.is_equal_approx(projection.get("scene_transform")), context + " scene container transform did not apply")


func configure(projection: Node2D) -> void:
	projection.set("viewport_size", Vector2i(311, 227))
	projection.set("camera_size", 187.35)
	projection.set("camera_position", Vector3(17.0, -9.0, 480.0))
	projection.set("sprite_position", Vector2(-114.75, -67.5))
	projection.set("scene_transform", Transform3D(Basis.from_euler(Vector3(0.02, 0.04, -0.03)).scaled(Vector3(0.95, 1.1, 1.05)), Vector3(3.0, -7.0, 2.0)))


func check_serialization(projection: Node2D) -> void:
	var packed := PackedScene.new()
	check(packed.pack(projection) == OK, "Projection could not be packed")
	check(packed.get_state().get_node_count() == 1, "Generated pipeline was serialized into the authored scene")
	var saved := ResourceSaver.save(packed, SCRATCH_PATH)
	check(saved == OK, "Projection could not be saved")
	if saved != OK:
		return
	var reloaded := ResourceLoader.load(SCRATCH_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(reloaded != null, "Projection could not be loaded after saving")
	if reloaded != null:
		check(reloaded.get_state().get_node_count() == 1, "Saved scene retained generated descendants")
		var restored := reloaded.instantiate() as Node2D
		for property_name: String in ["viewport_size", "camera_size", "camera_position", "sprite_position", "scene_transform"]:
			check(restored.get(property_name) == projection.get(property_name), "Save/load lost " + property_name)
		check(restored.get("scene") is PackedScene, "Save/load lost the exported content scene")
		check(restored.call("ensure_built"), "Reloaded projection could not rebuild itself")
		if check_pipeline(restored, "Saved/reloaded off-tree projection"):
			check_settings(restored, "Saved/reloaded projection")
			check(String(restored.get("scene_instance").name) == String(projection.get("scene_instance").name), "Save/load changed projected content")
		root.add_child(restored)
		check(restored.call("ensure_built"), "Reloaded projection could not enter the tree")
		var ids := identities(restored)
		restored.free()
		descendants_gone(ids, "Saved/reloaded projection cleanup")
	check(DirAccess.remove_absolute(SCRATCH_PATH) == OK, "Probe failed to remove scratch packed scene")


func check_isolation(projection: Node2D, scene: PackedScene) -> void:
	var other = ProjectionScript.new()
	other.scene = scene
	root.add_child(other)
	check(other.ensure_built(), "Second projection could not initialize")
	if not check_pipeline(other, "Second projection"):
		other.free()
		return
	var viewport: SubViewport = projection.get("viewport")
	var camera: Camera3D = projection.get("camera")
	check(viewport != other.viewport and viewport.find_world_3d() != other.viewport.find_world_3d(), "Instances share their viewport or 3D world")
	check(viewport.find_world_3d() != root.find_world_3d(), "Projection inherited the host's 3D world")
	check(viewport.get_texture() != other.viewport.get_texture() and projection.get("sprite").texture != other.sprite.texture, "Instances share viewport textures")
	check(camera != other.camera and camera.environment != other.camera.environment, "Instances share camera or mutable environment")
	check(projection.get("scene_instance") != other.scene_instance, "Instances share content nodes")
	var untouched_color: Color = other.camera.environment.ambient_light_color
	camera.environment.ambient_light_color = Color(0.13, 0.47, 0.79)
	check(other.camera.environment.ambient_light_color == untouched_color, "Mutating one environment affected another instance")
	var other_position: Vector3 = other.scene_instance.position
	projection.get("scene_instance").position += Vector3(5.0, 6.0, 7.0)
	check(other.scene_instance.position == other_position, "Mutating content affected another instance")
	var first_light := viewport.find_children("*", "Light3D", true, false)[0] as Light3D
	var second_light := other.viewport.find_children("*", "Light3D", true, false)[0] as Light3D
	var other_energy := second_light.light_energy
	first_light.light_energy += 0.5
	check(first_light != second_light and second_light.light_energy == other_energy, "Instances share generated light state")
	var ids := identities(other)
	other.free()
	descendants_gone(ids, "Second instance cleanup")


func check_optional_settings(scene: PackedScene) -> void:
	var projection = ProjectionScript.new()
	projection.scene = scene
	projection.viewport_update_mode = SubViewport.UPDATE_ALWAYS
	projection.camera_rotation = Vector3(0.1, -0.2, 0.3)
	projection.camera_keep_aspect = Camera3D.KEEP_WIDTH
	projection.camera_near = 0.25
	projection.camera_far = 777.0
	projection.sprite_centered = true
	projection.sprite_texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	projection.light_rotation = Vector3(-0.5, -0.3, 0.1)
	projection.light_color = Color(0.7, 0.8, 0.95)
	projection.light_energy = 0.625
	projection.light_shadow_enabled = true
	root.add_child(projection)
	check(projection.ensure_built(), "Optional settings projection failed to build")
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Viewport update mode was not applied")
	check(projection.camera.rotation.is_equal_approx(projection.camera_rotation), "Camera rotation was not applied")
	check(projection.camera.keep_aspect == Camera3D.KEEP_WIDTH, "Camera aspect mode was not applied")
	check(is_equal_approx(projection.camera.near, 0.25) and is_equal_approx(projection.camera.far, 777.0), "Camera clipping distances were not applied")
	check(projection.sprite.centered and projection.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "Sprite centering/filter was not applied")
	check(projection.light.rotation.is_equal_approx(projection.light_rotation), "Light rotation was not applied")
	check(projection.light.light_color.is_equal_approx(projection.light_color), "Light color was not applied")
	check(is_equal_approx(projection.light.light_energy, 0.625) and projection.light.shadow_enabled, "Light energy/shadows were not applied")
	var stable_ids := identities(projection)
	projection.viewport_update_mode = SubViewport.UPDATE_DISABLED
	projection.camera_rotation = Vector3(-0.3, 0.2, -0.1)
	projection.camera_keep_aspect = Camera3D.KEEP_HEIGHT
	projection.camera_near = 0.125
	projection.camera_far = 800.0
	projection.sprite_centered = false
	projection.sprite_texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	projection.light_rotation = Vector3(-0.1, -0.7, 0.2)
	projection.light_color = Color(0.25, 0.5, 0.75)
	projection.light_energy = 0.375
	projection.light_shadow_enabled = false
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Live viewport update mode did not apply")
	check(projection.camera.rotation.is_equal_approx(projection.camera_rotation), "Live camera rotation did not apply")
	check(projection.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "Live camera aspect mode did not apply")
	check(is_equal_approx(projection.camera.near, 0.125) and is_equal_approx(projection.camera.far, 800.0), "Live camera clipping did not apply")
	check(not projection.sprite.centered and projection.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Live sprite centering/filter did not apply")
	check(projection.light.rotation.is_equal_approx(projection.light_rotation), "Live light rotation did not apply")
	check(projection.light.light_color.is_equal_approx(projection.light_color), "Live light color did not apply")
	check(is_equal_approx(projection.light.light_energy, 0.375) and not projection.light.shadow_enabled, "Live light energy/shadows did not apply")
	check(identities(projection) == stable_ids, "Optional settings replaced generated nodes")
	# Invalid dimensions and clip values are normalized into valid renderer inputs.
	projection.viewport_size = Vector2i(0, -10)
	projection.camera_size = -100.0
	projection.camera_near = -2.0
	projection.camera_far = -3.0
	projection.light_energy = -1.0
	check(projection.viewport_size == Vector2i(2, 2) and projection.viewport.size == Vector2i(2, 2), "Viewport size clamp must match Godot minimum dimensions")
	check(projection.camera_size > 0.0 and projection.camera.size > 0.0, "Camera size clamp failed")
	check(projection.camera.near > 0.0 and projection.camera.far > projection.camera.near, "Camera clip clamp failed")
	check(projection.light_energy == 0.0 and projection.light.light_energy == 0.0, "Light energy clamp failed")
	projection.camera_near = 20.0
	projection.camera_far = 10.0
	check(projection.camera.far > projection.camera.near, "Near/far inversion produced an invalid frustum")
	# A provided environment and nested sky/material must also be private copies.
	var template := Environment.new()
	template.ambient_light_color = Color(0.2, 0.4, 0.6)
	template.sky = Sky.new()
	template.sky.sky_material = ProceduralSkyMaterial.new()
	projection.environment = template
	var other = ProjectionScript.new()
	other.scene = scene
	other.environment = template
	root.add_child(other)
	check(other.ensure_built(), "Shared-template projection did not build")
	check(projection.camera.environment != template and other.camera.environment != template, "A camera uses the environment template directly")
	check(projection.camera.environment != other.camera.environment, "Provided environment template was shared between cameras")
	check(projection.camera.environment.sky != template.sky and projection.camera.environment.sky != other.camera.environment.sky, "Environment sky resource was not deep-duplicated")
	check(projection.camera.environment.sky.sky_material != template.sky.sky_material and projection.camera.environment.sky.sky_material != other.camera.environment.sky.sky_material, "Environment sky material was not deep-duplicated")
	check(projection.camera.environment.ambient_light_color.is_equal_approx(template.ambient_light_color), "Environment template values were not copied")
	projection.camera.environment.ambient_light_color = Color(0.9, 0.1, 0.2)
	check(other.camera.environment.ambient_light_color.is_equal_approx(template.ambient_light_color), "Mutating duplicated environment leaked to another instance/template")
	template.ambient_light_color = Color(0.6, 0.5, 0.4)
	template.emit_changed()
	check(projection.camera.environment.ambient_light_color.is_equal_approx(template.ambient_light_color) and other.camera.environment.ambient_light_color.is_equal_approx(template.ambient_light_color), "Environment resource changed signal did not refresh private copies")
	check(projection.camera.environment != other.camera.environment, "Refreshing environment template introduced sharing")
	projection.environment = null
	check(projection.camera.environment != null and projection.camera.environment != template, "Clearing template did not restore a private default environment")
	# Hand-authored children are outside the generated helper ownership boundary.
	var authored := Node2D.new()
	authored.name = "AuthoredOverlay"
	projection.add_child(authored)
	authored.owner = projection
	check(projection.rebuild(), "Rebuild with an authored child failed")
	check(is_instance_valid(authored) and authored.get_parent() == projection, "Rebuild destroyed an authored child")
	check(projection.get_child_count() == 1, "Generated nodes escaped internal-only enumeration")
	var packed := PackedScene.new()
	check(packed.pack(projection) == OK and packed.get_state().get_node_count() == 2, "Packing did not preserve only the projection and authored child")
	var ids := identities(other)
	other.free()
	descendants_gone(ids, "Environment-template peer cleanup")
	ids = identities(projection)
	projection.free()
	descendants_gone(ids, "Optional-settings projection cleanup")


func check_signal_contract(scene: PackedScene, invalid_scene: PackedScene) -> void:
	var projection = ProjectionScript.new()
	projection.scene = scene
	var events: Array[String] = []
	var previous_ids: Array[int] = []
	projection.rebuilding.connect(func():
		events.append("rebuilding")
		for identity: int in previous_ids:
			check(is_instance_id_valid(identity), "rebuilding emitted after old generated nodes were destroyed")
	)
	projection.rebuilt.connect(func():
		events.append("rebuilt")
		check(is_instance_valid(projection.viewport) and is_instance_valid(projection.camera) and is_instance_valid(projection.sprite), "rebuilt emitted before public references were ready")
	)
	projection.build_failed.connect(func(message: String):
		events.append("build_failed")
		check(message.contains("Node3D") and message.contains("Node2D"), "build_failed message does not explain the rejected root type")
		check(projection.get_child_count(true) == 0, "build_failed emitted with a partially built pipeline")
	)
	check(projection.ensure_built(), "Signal-contract initial build failed")
	check(events == ["rebuilding", "rebuilt"], "Initial build signal order is wrong")
	events.clear()
	previous_ids.assign(generated_ids(projection))
	check(projection.rebuild(), "Signal-contract rebuild failed")
	check(events == ["rebuilding", "rebuilt"], "Rebuild signal order is wrong")
	events.clear()
	previous_ids.clear()
	check(projection.ensure_built() and events.is_empty(), "Idempotent ensure emitted lifecycle signals")
	scene.emit_changed()
	check(projection.ensure_built(), "Scene resource changed signal did not rebuild off-tree content")
	check(events == ["rebuilding", "rebuilt"], "Changed scene resource emitted the wrong lifecycle sequence")
	events.clear()
	projection.scene = invalid_scene
	print("PROJECTION_3D_EXPECTED_INVALID_SIGNAL_BEGIN")
	check(not projection.ensure_built(), "Signal-contract invalid root unexpectedly succeeded")
	print("PROJECTION_3D_EXPECTED_INVALID_SIGNAL_END")
	check(events == ["rebuilding", "build_failed"], "Failed build emitted the wrong lifecycle sequence")
	events.clear()
	check(not projection.ensure_built() and events.is_empty(), "Unchanged invalid content repeated lifecycle notifications")
	projection.scene = scene
	check(projection.ensure_built() and events == ["rebuilding", "rebuilt"], "Recovery emitted the wrong lifecycle sequence")
	projection.free()


func check_packed_shell_and_redraw(scene: PackedScene) -> void:
	check(ProjectionScene.get_state().get_node_count() == 1, "Reusable scene must serialize only the configuration root")
	var projection = ProjectionScene.instantiate()
	check(projection.get_child_count(true) == 0, "Packed projection contains pre-generated helpers")
	projection.request_redraw()
	check(projection.ensure_built() and projection.scene_instance == null, "Reusable scene's default null-content shell failed")
	check(check_pipeline(projection, "Packed null-content shell"), "Packed scene did not build a valid shell")
	projection.scene = scene
	check(projection.ensure_built(), "Packed scene did not accept injected content")
	projection.viewport_update_mode = SubViewport.UPDATE_ALWAYS
	projection.request_redraw()
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Explicit redraw changed continuous rendering policy")
	projection.viewport_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	projection.request_redraw()
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "Explicit redraw changed visible-only rendering policy")
	projection.viewport_update_mode = SubViewport.UPDATE_DISABLED
	projection.camera_size += 1.0
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Setting change overrode intentionally disabled rendering")
	projection.request_redraw()
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE and projection.viewport_update_mode == SubViewport.UPDATE_DISABLED, "Explicit redraw did not request one frame while preserving configured policy")
	projection.viewport_update_mode = SubViewport.UPDATE_ONCE
	# Simulate consumption without claiming a headless GPU-rendered frame.
	projection.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projection.camera_size += 1.0
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE and projection.viewport_update_mode == SubViewport.UPDATE_ONCE, "Config change did not re-arm consumed single-frame rendering")
	projection.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projection.request_redraw()
	check(projection.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Explicit redraw did not re-arm consumed single-frame rendering")
	# Public accessors must be null-safe if an external caller removes a helper.
	for property_name: String in ["camera", "sprite", "viewport", "light", "scene_container", "scene_instance"]:
		var old_ids := generated_ids(projection)
		projection.get(property_name).free()
		check(projection.get(property_name) == null, "Accessor returned a freed helper: " + property_name)
		check(projection.ensure_built(), "ensure_built did not repair a removed helper: " + property_name)
		descendants_gone(old_ids, "Repair of " + property_name)
		check(check_pipeline(projection, "Repair of " + property_name), "Repair left an invalid pipeline")
	for property_name: String in ["camera", "sprite", "viewport", "light", "scene_container", "scene_instance"]:
		var old_ids := generated_ids(projection)
		var detached: Node = projection.get(property_name)
		detached.get_parent().remove_child(detached)
		check(projection.ensure_built(), "ensure_built did not repair a detached helper: " + property_name)
		descendants_gone(old_ids, "Detached helper repair: " + property_name)
		check(check_pipeline(projection, "Detached helper repair: " + property_name), "Detached helper repair left an invalid pipeline")
	var ids := identities(projection)
	projection.free()
	descendants_gone(ids, "Packed projection cleanup")


func run() -> void:
	if Engine.is_editor_hint():
		await create_timer(0.25).timeout
		var filesystem := EditorInterface.get_resource_filesystem()
		while filesystem.is_scanning():
			await create_timer(0.05).timeout
	await frames()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var scene_a := make_scene("AlphaContent")
	var scene_b := make_scene("BetaContent")
	var invalid_scene := make_scene("Invalid2DRoot", false)
	var projection = ProjectionScript.new()
	projection.name = "StandaloneProjection"
	check(projection is Node2D and projection.get_script().is_tool(), "Projection3D must be a @tool Node2D")
	for property_name: String in ["scene", "viewport_size", "camera_size", "camera_position", "sprite_position", "scene_transform"]:
		var expected_type: int = {"scene": TYPE_OBJECT, "viewport_size": TYPE_VECTOR2I, "camera_size": TYPE_FLOAT, "camera_position": TYPE_VECTOR3, "sprite_position": TYPE_VECTOR2, "scene_transform": TYPE_TRANSFORM3D}[property_name]
		check(is_exported(projection, property_name, expected_type), "Missing typed exported property: " + property_name)
	check(projection.has_signal("rebuilt"), "Public rebuilt signal is missing")
	projection.rebuilt.connect(func(): rebuilt_count += 1)
	projection.scene = scene_a
	configure(projection)
	check(projection.ensure_built(), "First pre-_ready build failed")
	if not check_pipeline(projection, "Pre-_ready projection"):
		projection.free()
		quit(1)
		return
	check_settings(projection, "Pre-_ready projection")
	check(String(projection.scene_instance.name) == "AlphaContent", "Wrong packed scene was instantiated")
	check(projection.scene_instance.get_parent() == projection.scene_container, "Content is not under scene_container")
	check(projection.scene_instance.position == Vector3(3.0, 4.0, 5.0), "Container transform overwrote authored content transform")
	check(rebuilt_count == 1, "Successful initial build must emit rebuilt once")
	var stable_ids := identities(projection)
	for iteration in 8:
		check(projection.ensure_built(), "Repeated pre-ready ensure failed at iteration " + str(iteration))
		check(identities(projection) == stable_ids, "Repeated pre-ready ensure replaced or accumulated nodes")
	check(rebuilt_count == 1, "Idempotent ensure incorrectly emitted rebuilt")
	root.add_child(projection)
	await frames()
	check(identities(projection) == stable_ids, "Entering the tree rebuilt an existing pipeline")
	for iteration in 8:
		check(projection.ensure_built(), "Repeated post-ready ensure failed at iteration " + str(iteration))
		check(identities(projection) == stable_ids, "Repeated post-ready ensure replaced or accumulated nodes")
	check_settings(projection, "Post-ready projection")
	check(rebuilt_count == 1, "Tree entry/idempotent ensure incorrectly emitted rebuilt")
	# Property setters must update the live helper, without resetting other helpers.
	projection.camera.rotation = Vector3(0.13, -0.2, 0.03)
	projection.sprite.scale = Vector2(1.2, 0.8)
	var authored_camera_rotation: Vector3 = projection.camera.rotation
	var authored_sprite_scale: Vector2 = projection.sprite.scale
	projection.viewport_size = Vector2i(297, 181)
	projection.camera_size = 153.75
	projection.camera_position = Vector3(13.25, -27.5, 470.0)
	projection.sprite_position = Vector2(-100.5, -80.25)
	projection.scene_transform = Transform3D(Basis.from_euler(Vector3(-0.1, 0.2, 0.3)), Vector3(9.0, -8.0, 7.0))
	await frames()
	check(projection.ensure_built(), "Applying live settings invalidated the pipeline")
	check_settings(projection, "Live settings update")
	check(identities(projection) == stable_ids, "Live settings recreated the pipeline or content")
	check(projection.camera.rotation.is_equal_approx(authored_camera_rotation), "Unrelated setting overwrote direct camera rotation")
	check(projection.sprite.scale == authored_sprite_scale, "Unrelated setting overwrote direct sprite scale")
	check(rebuilt_count == 1, "Live non-scene settings unexpectedly emitted rebuilt")
	check_isolation(projection, scene_a)
	check_serialization(projection)
	# A forced rebuild replaces and frees every generated node exactly once.
	var old_ids := generated_ids(projection)
	check(projection.rebuild(), "Explicit rebuild failed")
	descendants_gone(old_ids, "Explicit rebuild")
	check(check_pipeline(projection, "Explicit rebuild"), "Explicit rebuild produced an incomplete pipeline")
	check_settings(projection, "Explicit rebuild")
	check(rebuilt_count == 2, "Explicit rebuild must emit rebuilt once")
	var populated_node_count := all_nodes(projection).size()
	for iteration in 6:
		old_ids = generated_ids(projection)
		check(projection.rebuild(), "Repeated rebuild failed at iteration " + str(iteration))
		descendants_gone(old_ids, "Repeated rebuild")
		check(all_nodes(projection).size() == populated_node_count, "Repeated rebuild accumulated children")
	# Scene changes are applied synchronously by ensure_built, then deferred work is harmless.
	old_ids = generated_ids(projection)
	projection.scene = scene_b
	check(projection.ensure_built(), "Replacing content scene failed")
	check(String(projection.scene_instance.name) == "BetaContent", "Scene replacement retained the old content")
	descendants_gone(old_ids, "Scene replacement")
	stable_ids = identities(projection)
	var replacement_signals := rebuilt_count
	await frames()
	check(identities(projection) == stable_ids and rebuilt_count == replacement_signals, "Queued scene update rebuilt after synchronous ensure")
	projection.scene = scene_a
	await frames()
	check(String(projection.scene_instance.name) == "AlphaContent", "Deferred scene change was not applied in tree")
	check(projection.ensure_built(), "Deferred replacement was not a valid built pipeline")
	# Null content is a valid empty projection shell, with no stale content.
	old_ids = generated_ids(projection)
	projection.scene = null
	check(projection.ensure_built(), "Null scene should produce a valid empty shell")
	check(projection.scene_instance == null, "Null scene retained content")
	check(check_pipeline(projection, "Empty shell"), "Null scene lost the pipeline")
	descendants_gone(old_ids, "Null scene replacement")
	check(projection.scene_container.get_child_count(true) == 0, "Empty shell contains stale content")
	var empty_ids := identities(projection)
	for _iteration in 4:
		check(projection.ensure_built() and identities(projection) == empty_ids, "Null scene ensure was not idempotent")
	# Deliberate rejection: errors below must clearly identify the wrong root type.
	print("PROJECTION_3D_EXPECTED_INVALID_ROOT_BEGIN")
	projection.scene = invalid_scene
	check(not projection.ensure_built(), "Node2D scene root was incorrectly accepted")
	check(projection.scene_instance == null, "Invalid scene leaked its root through scene_instance")
	check(projection.get_child_count(true) == 0, "Invalid scene left a partial generated pipeline")
	var invalid_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for _iteration in 3:
		check(not projection.ensure_built(), "Repeated ensure accepted an invalid scene")
		check(projection.get_child_count(true) == 0, "Repeated invalid build accumulated children")
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == invalid_orphans, "Repeated invalid build leaked orphan nodes")
	print("PROJECTION_3D_EXPECTED_INVALID_ROOT_END")
	projection.scene = scene_b
	check(projection.ensure_built(), "Projection did not recover after replacing invalid scene")
	check(check_pipeline(projection, "Invalid-root recovery"), "Recovery did not rebuild a complete pipeline")
	check(String(projection.scene_instance.name) == "BetaContent", "Recovery instantiated the wrong scene")
	stable_ids = identities(projection)
	var reentry_signals := rebuilt_count
	for _iteration in 4:
		root.remove_child(projection)
		check(projection.ensure_built(), "Off-tree ensure after removal failed")
		root.add_child(projection)
		await frames()
		check(projection.ensure_built(), "Ensure after tree reentry failed")
		check(identities(projection) == stable_ids, "Tree reentry duplicated or replaced generated nodes")
	check(rebuilt_count == reentry_signals, "Remove/readd unexpectedly emitted rebuilt")
	old_ids = generated_ids(projection)
	root.remove_child(projection)
	projection.scene = scene_a
	root.add_child(projection)
	await frames()
	check(projection.ensure_built() and String(projection.scene_instance.name) == "AlphaContent", "Scene changed while detached was not rebuilt on reentry")
	descendants_gone(old_ids, "Detached scene replacement")
	check(check_pipeline(projection, "Detached scene replacement"), "Detached scene replacement lost native content behavior")
	old_ids = identities(projection)
	projection.free()
	descendants_gone(old_ids, "Projection free")
	check_optional_settings(scene_a)
	check_signal_contract(scene_a, invalid_scene)
	check_packed_shell_and_redraw(scene_a)
	# Destruction before deferred rebuilding runs must cancel pending work safely.
	var doomed = ProjectionScript.new()
	root.add_child(doomed)
	doomed.scene = scene_a
	var doomed_ids := identities(doomed)
	doomed.free()
	await frames(3)
	descendants_gone(doomed_ids, "Free before deferred rebuild")
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_baseline, "Lifecycle test left orphan nodes")
	if not failed:
		print("PROJECTION_3D_LIFECYCLE_PASS checks=", checks, " editor_hint=", Engine.is_editor_hint())
	quit(1 if failed else 0)
