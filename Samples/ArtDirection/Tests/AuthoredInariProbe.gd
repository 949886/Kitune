extends SceneTree
## Save actual designer changes to each INARI .tscn, then verify runtime binding,
## native tilted coordinates, terrain queries and original camera configuration.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const PROFILES := "res://Samples/ArtDirection/Profiles/levels.json"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var checked := 0
	for profile: Dictionary in Assets.read_json(PROFILES):
		if profile.kind != "original_2d":
			continue
		assert(not profile.has("spawn") and not profile.has("objectives"))
		var packed: PackedScene = load(profile.stage_scene)
		var edited: Node2D = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var visual: Node2D
		for candidate: Node2D in edited.scenery_root.find_children("*", "Node2D", true, false):
			if (
				candidate.has_method("prepare")
				and not candidate.source_item.get("spatial", {}).get("parallel", true)
			):
				visual = candidate
				break
		assert(visual != null)
		visual.source_animation_enabled = false
		visual.position += Vector2(32, -16)
		visual.modulate = Color(0.8, 0.6, 0.4, 0.3)
		var visual_path := edited.get_path_to(visual)
		var visual_pose := visual.transform
		var source_pose := Assets.matrix(visual.source_item.transform)
		var expected_spatial := (
			visual_pose
			* source_pose.affine_inverse()
			* Assets.matrix(visual.source_item.spatial.transform)
		)
		edited.authored_route.spawn_marker.position = Vector2(101, -203)
		edited.authored_route.objective_root.get_child(0).position = Vector2(31, 47)
		edited.authored_route.objective_root.get_child(0).radius = 67.0
		edited.camera_settings.lens.FieldOfView = 40.0
		if edited.authored_camera.fixed_target != null:
			edited.authored_camera.fixed_target.position = Vector2(83, -89)
		var light: Marker2D = edited.light_root.get_child(0)
		light.position += Vector2(7, 11)
		light.energy = 3.25
		var light_position := light.position
		# Add a standard Godot platform. Binding must not rebuild collision from JSON.
		var body := StaticBody2D.new()
		body.name = "DesignerPlatform"
		body.collision_layer = 1
		body.position = Vector2(10000, -10000)
		edited.terrain_root.add_child(body)
		body.owner = edited
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(72, 16)
		shape.shape = rectangle
		body.add_child(shape)
		shape.owner = edited
		var terrain_count: int = edited.terrain_root.get_child_count()
		var old_body: CollisionObject2D = edited.terrain_root.get_child(0)
		old_body.position += Vector2(17, 19)
		var body_path := edited.get_path_to(old_body)
		var body_position := old_body.position
		var saved := PackedScene.new()
		assert(saved.pack(edited) == OK)
		var output: String = "res://tmp/art-direction/edited-" + profile.id + ".tscn"
		assert(ResourceSaver.save(saved, output) == OK)
		edited.free()

		var reloaded: PackedScene = ResourceLoader.load(
			output, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
		)
		var stage: Node2D = reloaded.instantiate()
		root.add_child(stage)
		stage.configure("", profile)
		stage.process_mode = Node.PROCESS_MODE_DISABLED
		stage.terrain_root.process_mode = Node.PROCESS_MODE_ALWAYS
		var actual: Node2D = stage.get_node(visual_path)
		assert(actual.transform.is_equal_approx(visual_pose))
		assert(actual.modulate.is_equal_approx(Color(0.8, 0.6, 0.4, 0.3)))
		assert(Assets.matrix(actual.data.spatial.transform).is_equal_approx(expected_spatial))
		assert(Assets.vec(profile.spawn) == Vector2(101, -203))
		assert(Assets.vec(profile.objectives[0].position) == Vector2(31, 47))
		assert(profile.objectives[0].radius == 67.0)
		assert(stage.solid_count == terrain_count)
		assert(stage.get_node(body_path).position == body_position)
		assert(stage.data.lights[0].energy == 3.25)
		assert(Assets.matrix(stage.data.lights[0].spatial.transform).origin == light_position)
		assert(stage.source_camera.lens.FieldOfView == 40.0)
		assert(stage.authored_camera.get_script().resource_path.ends_with("InariCameraRig.gd"))
		if stage.authored_camera.fixed_target != null:
			assert(stage.authored_camera.fixed_target.position == Vector2(83, -89))
		for frame in 3:
			await physics_frame
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Vector2(10000, -10000)
		query.collision_mask = 1
		var hits := stage.get_world_2d().direct_space_state.intersect_point(query)
		assert(hits.size() == 1 and hits[0].collider.name == "DesignerPlatform")
		stage.queue_free()
		await process_frame
		checked += 1
	assert(checked == 2)
	print("AUTHORED_INARI_PASS scenes=2 edits=preserved physics=active")
	quit()
