extends SceneTree
## Explicit conversion of the selected INARI studies to editable Godot content.
## Source animation/controller archives remain available for runtime behavior.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const OriginalStage = preload("res://Samples/ArtDirection/Runtime/OriginalStage.gd")
const Stage = preload("res://Samples/ArtDirection/Runtime/AuthoredInariStage.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/InariSceneSprite.gd")
const Light = preload("res://Samples/ArtDirection/Runtime/InariSceneLight.gd")
const EnemySpawn = preload("res://Samples/ArtDirection/Runtime/InariEnemySpawn.gd")
const Record = preload("res://Samples/ArtDirection/Runtime/OriginalSceneRecord.gd")
const Hazard = preload("res://Samples/ArtDirection/Runtime/StudyHazard.gd")
const Route = preload("res://Samples/ArtDirection/Runtime/StudyRoute.gd")
const Waypoint = preload("res://Samples/ArtDirection/Runtime/StudyWaypoint.gd")
const CameraRig = preload("res://Samples/ArtDirection/Runtime/InariCameraRig.gd")
const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const SELECTION := "res://Samples/ArtDirection/Tools/inari_scene_selection.json"

var level: Node2D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for config: Dictionary in Assets.read_json(SELECTION):
		_export(config)
	quit()


func _export(config: Dictionary) -> void:
	var source := OriginalStage.new()
	root.add_child(source)
	source.configure(Assets.ROOT + config.scene_data, config)
	level = Stage.new()
	level.name = config.output.get_file().get_basename()
	root.add_child(level)
	level.source_archive = Assets.ROOT + config.scene_data
	level.camera_settings = source.source_camera.duplicate(true)
	level.scenery_root = _add(Node2D.new(), level, "Scenery")
	level.terrain_root = _add(Node2D.new(), level, "Terrain")
	level.light_root = _add(Node2D.new(), level, "Lights")
	level.spawn_root = _add(Node2D.new(), level, "EnemySpawns")
	level.trigger_root = _add(Node2D.new(), level, "WindStations")
	var planes := {}
	for key: Vector2 in source.projection.planes:
		var original: Node2D = source.projection.planes[key]
		var plane: Node2D = _add(Node2D.new(), level.scenery_root, "Depth_%03d" % planes.size())
		plane.transform = original.transform
		plane.visible = original.visible
		plane.set_meta("native_depth", key.x)
		plane.set_meta("follow_camera_x", original.get_meta("follow_camera_x", false))
		planes[original] = plane
	for index in source.visual_instances.size():
		var original: Node2D = source.visual_instances[index]
		var parent: Node2D = planes.get(original.get_parent(), level.scenery_root)
		var label := "Sprite_%04d" % index
		if original.data.sprite != null:
			label += "_" + str(Assets.sprite_info(original.data.sprite).name).validate_node_name()
		var visual: Node2D = _add(Visual.new(), parent, label)
		visual.source_item = original.data.duplicate(true)
		visual.transform = original.transform
		visual.z_index = original.z_index
		visual.visible = original.visible
		visual.modulate = original.modulate
	for original: Node in source.get_children():
		if not (
			original is StaticBody2D
			or (original is Area2D and not original in source.wind_triggers)
		):
			continue
		if original is Area2D:
			_clear_signal(original, "body_entered")
			original.set_script(Hazard)
		original.reparent(level.terrain_root, false)
		original.owner = level
		_own(original)
	for index in source.data.lights.size():
		var item: Dictionary = source.data.lights[index]
		var light: Marker2D = _add(
			Light.new(), level.light_root, "Light_%03d_%s" % [index, item.name]
		)
		light.definition = item.duplicate(true)
		light.transform = Assets.matrix(item.spatial.transform)
		light.light_color = Assets.color(item.color)
		light.energy = item.energy
		light.radius = item.radius
		light.depth = item.spatial.depth
	for index in source.data.enemies.size():
		var item: Dictionary = source.data.enemies[index]
		var marker: Marker2D = _add(
			EnemySpawn.new(), level.spawn_root, "Enemy_%02d_%s" % [index, item.kind]
		)
		marker.position = Assets.vec(item.position)
		var definition := Record.new()
		definition.resource_local_to_scene = true
		definition.data = item.duplicate(true)
		marker.definition = definition
	for index in source.wind_triggers.size():
		var original: Area2D = source.wind_triggers[index]
		_clear_signal(original, "body_entered")
		_clear_signal(original, "began")
		_clear_signal(original, "cooled")
		original.name = "WindStation_%02d" % index
		original.set_meta("wind_source", original.source)
		original.set_meta("story_heal", original.story_heal)
		original.reparent(level.trigger_root, false)
		original.owner = level
		_own(original)

	var player := Player.new()
	root.add_child(player)
	player.position = Assets.vec(config.spawn)
	if not source.player_idle.is_empty():
		player.position = (
			Assets.vec(source.player_idle.pose.root_position) - player.body_shape.position
		)
	_build_route(config, player.position)
	level.authored_camera = _add(CameraRig.new(), level, "OriginalCameraRig")
	level.authored_camera.configure_2d(config, player, source.source_camera)
	if source.source_camera.follow.has("fixed_position"):
		level.authored_camera.fixed_target = level.authored_camera.target
	_own(level.authored_camera)
	var output: String = config.output
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output_directory="):
			output = argument.trim_prefix("output_directory=").path_join(output.get_file())
	assert(DirAccess.make_dir_recursive_absolute(output.get_base_dir()) == OK)
	var packed := PackedScene.new()
	assert(packed.pack(level) == OK)
	assert(ResourceSaver.save(packed, output) == OK)
	print(
		"INARI_SCENE_EXPORTED ",
		output,
		" visuals=",
		source.visual_instances.size(),
		" terrain=",
		level.terrain_root.get_child_count()
	)
	player.free()
	source.free()
	level.free()


func _build_route(config: Dictionary, spawn: Vector2) -> void:
	level.authored_route = _add(Route.new(), level, "Route")
	var route: Node2D = level.authored_route
	route.spawn_marker = _add(Marker2D.new(), route, "PlayerSpawn")
	route.spawn_marker.position = spawn
	route.objective_root = _add(Node2D.new(), route, "Objectives")
	route.checkpoint_root = _add(Node2D.new(), route, "Checkpoints")
	for index in config.objectives.size():
		var item: Dictionary = config.objectives[index]
		var marker: Marker2D = _add(Waypoint.new(), route.objective_root, "Waypoint_%02d" % index)
		marker.position = Assets.vec(item.position)
		marker.label = item.name
		marker.radius = item.radius
		if item.has("kunai_anchor"):
			marker.kunai_anchor = _add(Marker2D.new(), marker, "KunaiAnchor")
			marker.kunai_anchor.position = Assets.vec(item.kunai_anchor) - marker.position
	for index in config.get("checkpoints", []).size():
		var marker: Marker2D = _add(
			Marker2D.new(), route.checkpoint_root, "Checkpoint_%02d" % index
		)
		marker.position = Assets.vec(config.checkpoints[index])


func _add(node: Node, parent: Node, label: String) -> Node:
	node.name = label.validate_node_name()
	parent.add_child(node)
	node.owner = level
	return node


func _own(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.name = (
			"Collision" if child is CollisionShape2D or child is CollisionPolygon2D else child.name
		)
		child.owner = level
		_own(child)


func _clear_signal(node: Node, key: String) -> void:
	for connection: Dictionary in node.get_signal_connection_list(key):
		node.disconnect(key, connection.callable)
