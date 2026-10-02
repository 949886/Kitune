extends "res://Samples/ArtDirection/Runtime/OriginalStage.gd"
## Bind native INARI behavior to saved scene content. Sprite/terrain/light/spawn
## placement is read from nodes; the source archive supplies animation and rules.

@export_file("*.json") var source_archive := ""
@export var scenery_root: Node2D
@export var terrain_root: Node2D
@export var light_root: Node2D
@export var spawn_root: Node2D
@export var trigger_root: Node2D
@export var authored_route: Node2D
@export var authored_camera: Node
@export var camera_settings: Dictionary


func configure(_path: String, options: Dictionary = {}) -> void:
	assert(visual_instances.is_empty(), "Configure an authored stage once")
	_create_runtime_modules()
	data = Assets.read_json(source_archive)
	var ambient := {}
	if options.has("ambient_animation"):
		ambient = Assets.read_json(Assets.ROOT + options.ambient_animation)
		assert(ambient.source == data.source)
	player_idle = ambient.get("player_idle", {})
	source_camera = camera_settings.duplicate(true)
	authored_route.apply_to(options)
	spawn = Assets.vec(options.spawn)
	data.lights = []
	for light: Node2D in light_root.get_children():
		data.lights.append(light.source_data())
	data.enemies = []
	for marker: Marker2D in spawn_root.get_children():
		data.enemies.append(marker.source_data())
	add_child(audio)
	add_child(combat_clock)
	add_child(chromatic)
	add_child(projection)
	projection.configure(source_camera)
	for plane: Node2D in scenery_root.get_children():
		if plane.has_meta("native_depth"):
			projection.register_authored(plane)
	add_child(lighting)
	lighting.configure(data, projection, false, [TargetMarker.light_source()])
	_build_doors()
	var visual_data: Array = []
	var animated_visuals := {}
	for visual: Node2D in scenery_root.find_children("*", "Node2D", true, false):
		if not visual.has_method("prepare"):
			continue
		visual.prepare()
		visual_instances.append(visual)
		visual_data.append(visual.data)
		visual.animation_material_changed.connect(_on_animation_material_changed.bind(visual))
		lighting.apply_to(visual, visual.data)
		projection.register_tilted(visual, visual.data.get("spatial", {}))
		if visual.data.has("go"):
			visuals_by_go[visual.data.go] = visual
			if visual.source_animation_enabled:
				animated_visuals[visual.data.go] = visual
		if door_pieces.has(visual.data.get("go", -1)):
			door_pieces[visual.data.go].visuals.append(visual)
	_index_sorting_orders(visual_data)
	add_child(sorting_capture)
	sorting_capture.configure(sort_depth)
	for body: CollisionObject2D in terrain_root.find_children(
		"*", "CollisionObject2D", true, false
	):
		solid_count += 1
		var go: Variant = body.get_meta("source_go", -1)
		if body is DoorPart and door_pieces.has(go):
			body.door = door_pieces[go].door
			door_pieces[go].bodies.append(body)
	add_child(animation)
	animation.configure(data.animations, animated_visuals)
	if not ambient.is_empty():
		animation.replace_sprite_tracks(ambient.tracks, animated_visuals)
	_bind_wind()
	navigation.configure(data.get("navigation", {}))
	for marker: Marker2D in spawn_root.get_children():
		var enemy_data: Dictionary = marker.source_data()
		var original: Dictionary = marker.definition.data
		var offset := marker.global_position - Assets.vec(original.position)
		for go: Variant in enemy_data.visuals:
			if visuals_by_go.has(go):
				visuals_by_go[go].global_position += offset
		var enemy := Enemy.new()
		enemy.name = str(marker.name) + "_Actor"
		add_child(enemy)
		enemy.configure(enemy_data, visuals_by_go, animation, navigation, sort_depth)
		enemies.append(enemy)


func _bind_wind() -> void:
	var wind_visuals: Dictionary = Assets.read_json(Assets.ROOT + "wind_animation.json")
	for trigger: Area2D in trigger_root.get_children():
		trigger.source = trigger.get_meta("wind_source").duplicate(true)
		trigger.story_heal = int(trigger.get_meta("story_heal"))
		trigger.audio = audio
		trigger.body_entered.connect(trigger.enter)
		wind_triggers.append(trigger)
		for entry: Dictionary in wind_visuals.levels.get(data.source, []):
			if (
				int(entry.trigger_go) != int(trigger.source.go)
				or not visuals_by_go.has(entry.visual_go)
			):
				continue
			var player := WindAnimation.new()
			add_child(player)
			animation.release_visuals([entry.visual_go])
			player.configure(
				wind_visuals.controllers[entry.controller], visuals_by_go[entry.visual_go]
			)
			trigger.began.connect(player.set_trigger.bind("On"))
			trigger.cooled.connect(player.set_trigger.bind("Off"))
			wind_animations.append(player)
