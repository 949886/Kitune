extends Node2D
signal scene_change_requested(record: Dictionary)
## Native behavior and source conversion shared by the importer and probes.
## Playable levels use AuthoredInariStage with saved .tscn content.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const WindTrigger = preload("res://Samples/ArtDirection/Runtime/InariWindTrigger.gd")
const Checkpoint = preload("res://Samples/ArtDirection/Runtime/InariCheckpoint.gd")
const Hazard = preload("res://Samples/ArtDirection/Runtime/StudyHazard.gd")
const Machinery = preload("res://Samples/ArtDirection/Runtime/InariMachinery.gd")
const CameraZones = preload("res://Samples/ArtDirection/Runtime/InariCameraZones.gd")
const WindAnimation = preload("res://Samples/ArtDirection/Runtime/InariWindAnimation.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const Door = preload("res://Samples/ArtDirection/Runtime/OriginalDoor.gd")
const DoorPart = preload("res://Samples/ArtDirection/Runtime/OriginalDoorPart.gd")
const Audio = preload("res://Samples/ArtDirection/Runtime/OriginalAudio.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const SceneAnimation = preload("res://Samples/ArtDirection/Runtime/OriginalSceneAnimation.gd")
const SceneProjection = preload("res://Samples/ArtDirection/Runtime/OriginalSceneProjection.gd")
const Lighting = preload("res://Samples/ArtDirection/Runtime/OriginalLighting.gd")
const Enemy = preload("res://Samples/ArtDirection/Runtime/OriginalEnemy.gd")
const Navigation = preload("res://Samples/ArtDirection/Runtime/OriginalNavigation.gd")
const ParticleEffect = preload("res://Samples/ArtDirection/Runtime/OriginalParticleEffect.gd")
const Arrow = preload("res://Samples/ArtDirection/Runtime/OriginalArrow.gd")
const TargetMarker = preload("res://Samples/ArtDirection/Runtime/InariTargetMarker.gd")
const TimeDomain = preload("res://Samples/ArtDirection/Runtime/InariTimeDomain.gd")
const Chromatic = preload("res://Samples/ArtDirection/Runtime/InariChromatic.gd")
const SortingCapture = preload("res://Samples/ArtDirection/Runtime/OriginalSortingCapture.gd")

signal effect_started(effect: Node2D)
signal arrow_started(arrow: RigidBody2D)
signal kunai_retired(kunai: Sprite2D)
signal kunai_ghost_started(ghost: Sprite2D)

var data: Dictionary
var source_camera: Dictionary
var player_idle: Dictionary
var spawn := Vector2.ZERO
var solid_count := 0
var ceiling_stuck_layers: Array
var door_pieces: Dictionary = {}
var audio: Audio
var sorting_orders: Array[Array] = []
var sorting_depths: Dictionary = {}
var projectile_layers: Array = []
var door_debris_layers: Array = []
var arrow_layers: Array = []
var visuals_by_go: Dictionary = {}
var visual_instances: Array[Node2D] = []
var animation: SceneAnimation
var projection: SceneProjection
var lighting: Lighting
var enemies: Array[Node] = []
var navigation := Navigation.new()
var combat_clock: TimeDomain
var chromatic: Chromatic
var sorting_capture: SortingCapture
var wind_triggers: Array[Node] = []
var wind_animations: Array[Node] = []
var source_checkpoints: Array[Area2D] = []
var spike_hazards: Array[Area2D] = []
var machinery: Node
var scene_options: Dictionary = {}
var camera_zones: Node


func bind_camera_zones(player: Node, rig: Node, is_loading: Callable) -> void:
	camera_zones = CameraZones.new()
	add_child(camera_zones)
	camera_zones.configure(self, player, rig, is_loading)


func bind_source_mechanisms(player: Node) -> void:
	# Wind visuals/triggers are built before the actor. Bind after its creation,
	# avoiding a preload of the entire player controller in a portable trigger.
	for trigger: Node in wind_triggers:
		trigger.bound_player = weakref(player)
	machinery = Machinery.new()
	add_child(machinery)
	machinery.configure(self, player)
	var rules: Dictionary = Assets.read_json(Assets.ROOT + "checkpoint_hazards.json")
	var scene: Dictionary = rules.levels.get(data.source, {})
	for record: Dictionary in scene.get("checkpoints", []):
		var checkpoint := Checkpoint.new()
		checkpoint.name = "SourceCheckpoint_" + str(record.go)
		checkpoint.configure(record, player)
		add_child(checkpoint)
		source_checkpoints.append(checkpoint)
	for record: Dictionary in scene.get("spikes", []):
		var hazard: Area2D
		# Prefer authored geometry if an editor scene already contains this GO.
		for area: Node in find_children("*", "Area2D", true, false):
			if (
				area.has_method("configure_spike")
				and int(area.get_meta("source_go", -1)) == int(record.go)
			):
				hazard = area
				break
		if hazard == null:
			hazard = Hazard.new()
			hazard.name = "SourceSpike_" + str(record.go)
			hazard.transform = Assets.matrix(record.transform)
			hazard.collision_layer = 0
			hazard.set_meta("source_go", int(record.go))
			for shape: Dictionary in record.shapes:
				for path: Array in shape.paths:
					var polygon := CollisionPolygon2D.new()
					var points := PackedVector2Array()
					for point: Array in path:
						points.append(Assets.vec(point))
					polygon.polygon = points
					polygon.position = Assets.vec(shape.offset)
					# A trigger occupies its interior, not only polygon edges.
					hazard.add_child(polygon)
			add_child(hazard)
		hazard.configure_spike(float(rules.spike_damage), player)
		spike_hazards.append(hazard)


func configure(path: String, options: Dictionary = {}) -> void:
	scene_options = options
	_create_runtime_modules()
	data = Assets.read_json(path)
	var ambient := {}
	if options.has("ambient_animation"):
		ambient = Assets.read_json(Assets.ROOT + options.ambient_animation)
		assert(ambient.source == data.source)
	player_idle = ambient.get("player_idle", {})
	source_camera = Assets.read_json(Assets.ROOT + "camera.json")
	if ambient.has("camera"):
		# The conversation excerpt uses its bound virtual camera and ShotPoint.
		# Output-camera impulses still come from the persistent camera manager.
		source_camera.merge(ambient.camera, true)
		source_camera.sha256 = ambient.source_sha256[source_camera.source]
	projectile_layers = Assets.read_json(Assets.ROOT + "controls.json").projectile_collision_layers
	door_debris_layers = Assets.read_json(Assets.ROOT + "door_physics.json").collision_layers
	arrow_layers = Assets.read_json(Arrow.DATA_PATH).collision_layers
	ceiling_stuck_layers = Assets.read_json(Assets.ROOT + "climb.json").ceiling.stuck_layers
	spawn = Assets.vec(data.spawn)
	add_child(audio)
	add_child(combat_clock)
	add_child(chromatic)
	add_child(projection)
	projection.configure(source_camera)
	add_child(lighting)
	lighting.configure(data, projection, false, [TargetMarker.light_source()])
	_build_doors()

	# Flatten tile cells and SpriteRenderers into one original sorting sequence.
	var visuals: Array = data.sprites.duplicate()
	var excluded_actor_visuals: Array = []
	if not options.get("enable_enemies", true):
		for enemy_data: Dictionary in data.get("enemies", []):
			excluded_actor_visuals.append_array(enemy_data.visuals)
	elif options.get("battle_only", false):
		for enemy_data: Dictionary in data.get("enemies", []):
			if not enemy_data.has("weakpoint_binding"):
				excluded_actor_visuals.append_array(enemy_data.visuals)
	for layer: Dictionary in data.tiles:
		if options.get("physics_only_tilemaps", false) and str(layer.name).begins_with("Tilemap_"):
			continue
		var base := Assets.matrix(layer.transform)
		var anchor := Assets.vec(layer.anchor)
		for cell: Array in layer.tiles:
			var axes: Array = cell[4]
			var local := Transform2D(
				Vector2(axes[0], axes[1]),
				Vector2(axes[2], axes[3]),
				Vector2(cell[0] + anchor.x, -cell[1] - anchor.y) * 16.0
			)
			var world := base * local
			visuals.append(
				{
					"sprite": cell[2],
					"tilemap_go": layer.get("go", -1),
					"transform":
					[world.x.x, world.x.y, world.y.x, world.y.y, world.origin.x, world.origin.y],
					"sort": layer.sort,
					"layer_id": layer.layer_id,
					"color": cell[3],
					"flip": [false, false],
					"mode": 0,
					"size": [16, 16],
					"blend": "normal"
				}
			)

	# Apply source Timeline poses before indexing sorting orders or creating water copies.
	# Keep the serialized scene's hidden/initial state available for ordinary scene loads.
	for pose: Dictionary in ambient.get("poses", []):
		var found := false
		for index in visuals.size():
			if visuals[index].get("go", -1) == pose.go:
				visuals[index] = visuals[index].duplicate(true)
				visuals[index].merge(pose, true)
				found = true
				break
		assert(found, "Ambient Timeline pose has no source renderer")
	visuals.sort_custom(_sort_visuals)
	_index_sorting_orders(visuals)
	add_child(sorting_capture)
	sorting_capture.configure(sort_depth)
	for item: Dictionary in visuals:
		if item.get("go", -1) in excluded_actor_visuals:
			continue
		if (
			item.sprite != null
			and Assets.sprite_info(item.sprite).name in options.get("hidden_sprite_names", [])
		):
			continue
		if options.get("finish_cutscene_transition", false) and int(item.sort[0]) >= 8:
			# The original Timeline fades these screen-covering transition sprites out.
			continue

		var visual := Visual.new()
		var spatial: Dictionary = item.get("spatial", {})
		var visual_data := item.duplicate()
		if spatial.get("parallel", false):
			# Full source TRS also preserves 180-degree X/Y flips on parallel planes.
			visual_data.transform = spatial.transform

		visual.configure(visual_data)
		visual.animation_material_changed.connect(_on_animation_material_changed.bind(visual))
		visual_instances.append(visual)
		lighting.apply_to(visual, visual_data)
		visual.z_index = sorting_depths[JSON.stringify(item.sort)]
		var plane: Node2D = projection.parent_for(spatial)
		if plane != null:
			plane.add_child(visual)
		else:
			add_child(visual)
		projection.register_tilted(visual, spatial)

		if item.has("go"):
			visuals_by_go[item.go] = visual
		if door_pieces.has(item.get("go", -1)):
			door_pieces[item.go].visuals.append(visual)

	for item: Dictionary in data.colliders:
		_build_collider(item)

	add_child(animation)
	animation.configure(data.animations, visuals_by_go)
	if not ambient.is_empty():
		# The visual study can select an original Timeline excerpt independently of dialogue.
		animation.replace_sprite_tracks(ambient.tracks, visuals_by_go)
	var wind: Dictionary = Assets.read_json(Assets.ROOT + "wind_buff.json")
	var wind_visuals: Dictionary = Assets.read_json(Assets.ROOT + "wind_animation.json")
	for item: Dictionary in wind.levels.get(data.source, []):
		var trigger := WindTrigger.new()
		add_child(trigger)
		trigger.configure(item, int(wind.story_heal))
		trigger.audio = audio
		wind_triggers.append(trigger)
		for entry: Dictionary in wind_visuals.levels.get(data.source, []):
			if int(entry.trigger_go) != int(item.go):
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
	navigation.configure(data.get("navigation", {}))
	for enemy_data: Dictionary in data.get("enemies", []):
		if (
			not options.get("enable_enemies", true)
			or (options.get("battle_only", false) and not enemy_data.has("weakpoint_binding"))
		):
			continue
		var enemy := Enemy.new()
		add_child(enemy)
		enemy.configure(enemy_data, visuals_by_go, animation, navigation, sort_depth)
		enemies.append(enemy)


func _create_runtime_modules() -> void:
	# Scene instances opened only for editing/packing need no runtime helper nodes.
	assert(audio == null, "Configure the stage once per instance")
	audio = Audio.new()
	animation = SceneAnimation.new()
	projection = SceneProjection.new()
	lighting = Lighting.new()
	combat_clock = TimeDomain.new()
	chromatic = Chromatic.new()
	sorting_capture = SortingCapture.new()


func spawn_effect(
	key: String,
	point: Vector2,
	angle: float,
	flip := false,
	follow: Node2D = null,
	respects_time_scale := true
) -> Node2D:
	var effect := ParticleEffect.new()
	add_child(effect)
	effect.global_position = point
	effect.rotation = angle
	effect.scale.x = -1.0 if flip else 1.0
	effect.configure(key, sort_depth, follow)
	if respects_time_scale:
		combat_clock.subscribe(effect)
	effect_started.emit(effect)
	return effect


func spawn_arrow(
	point: Vector2, angle: float, speed: float, shooter: Node2D, damage := 1
) -> RigidBody2D:
	var arrow := Arrow.new()
	add_child(arrow)
	arrow.configure(self, point, angle, speed, shooter, damage)
	arrow_started.emit(arrow)
	return arrow


func _build_doors() -> void:
	for config: Dictionary in data.get("doors", []):
		var door := Door.new()
		door.data = config
		door.audio = audio
		add_child(door)

		for source_piece: Dictionary in config.pieces:
			var piece := source_piece.duplicate()
			piece.bodies = []
			piece.visuals = []
			piece.door = door
			door.pieces.append(piece)
			door_pieces[piece.go] = piece


func _sort_visuals(a: Dictionary, b: Dictionary) -> bool:
	return _order_less(a.sort, b.sort)


func _order_less(sa: Array, sb: Array) -> bool:
	for index in range(mini(sa.size(), sb.size())):
		if sa[index] != sb[index]:
			return sa[index] < sb[index]
	return sa.size() < sb.size()


func _on_animation_material_changed(key: String, visual: Node2D) -> void:
	var item: Dictionary = visual.data.duplicate()
	item.material = key
	lighting.apply_to(visual, item)
	# Animated enemy materials must not share later hit-flash modifications.
	if visual.material is ShaderMaterial:
		visual.material = visual.material.duplicate()


func _index_sorting_orders(visuals: Array) -> void:
	# Unity's order values can be negative and nested inside SortingGroups.
	# Rank the complete tuples: layer * 100 + order incorrectly hides gears
	# behind lower-layer scenery when their local order is -500 or -9999.
	sorting_orders.clear()
	sorting_depths.clear()
	var orders: Array = visuals.map(func(item: Dictionary): return item.sort)
	# Both orders can fall in the same scenery gap. Index them explicitly so
	# the native +1 ghost order remains above the live kunai in both viewports.
	var kunai: Dictionary = Assets.read_json(Assets.ROOT + "kunai_rendering.json")
	var afterimage: Dictionary = Assets.read_json(Assets.ROOT + "kunai_afterimage.json")
	orders.append(kunai.sort)
	orders.append([kunai.sort[0], kunai.sort[1] + afterimage.sortingOrderOffset])
	# A prefix tuple sorts before every order within the next source layer.
	orders.append(sorting_capture.settings.capture_order_before)
	for enemy: Dictionary in data.get("enemies", []):
		var presentation: Dictionary = enemy.get(
			"ranged_presentation", enemy.get("rifle_presentation", {})
		)
		for group in ["RotationSpriteInfos", "NonRotationHolderInfos"]:
			for part: Dictionary in presentation.get(group, []):
				for info: Dictionary in part.infos:
					orders.append(info.sort)
	orders.sort_custom(_order_less)
	for order: Array in orders:
		var key := JSON.stringify(order)
		if sorting_depths.has(key):
			continue

		sorting_depths[key] = sorting_orders.size() * 2
		sorting_orders.append(order)

	assert(sorting_orders.size() < 2048, "Original sorting groups exceed Godot's depth range")


func sort_depth(order: Array) -> int:
	# Reserve gaps for dynamic actors whose source order is absent from the map.
	for index in sorting_orders.size():
		if not _order_less(sorting_orders[index], order):
			return index * 2 if sorting_orders[index] == order else index * 2 - 1

	return sorting_orders.size() * 2


func _build_collider(item: Dictionary) -> CollisionObject2D:
	var body: CollisionObject2D
	if item.get("hazard", false):
		var area := Hazard.new()
		area.collision_layer = 0
		area.collision_mask = 2
		body = area
	else:
		body = DoorPart.new() if door_pieces.has(item.get("go", -1)) else StaticBody2D.new()
		body.collision_layer = Collision.ONE_WAY if item.one_way else Collision.SOLID
		body.collision_mask = Collision.PLAYER
		if item.get("layer", "") == "InteractiveWall":
			body.collision_layer |= Collision.INTERACTIVE_WALL
		if item.get("layer", "") in door_debris_layers:
			body.collision_layer |= Collision.DOOR_DEBRIS_TARGET
		if item.get("layer", "") in arrow_layers:
			body.collision_layer |= Collision.ARROW_SURFACE
		if item.get("layer", "") in ["Ground", "Wall", "HardWall", "Platform"]:
			body.collision_layer |= Collision.STATIC_SURFACE
		if item.get("layer", "") == "Default":
			body.collision_layer |= Collision.DEFAULT_ENTITY
		if item.get("layer", "") in ["Ground", "Wall", "HardWall", "Door", "Platform"]:
			body.collision_layer |= Collision.PARTICLE_SURFACE
		if item.get("layer", "") in ["Ground", "Wall", "HardWall", "InteractiveWall"]:
			body.collision_layer |= Collision.SIGHT_SURFACE | Collision.RAY_SURFACE
		elif item.get("layer", "") == "InteractiveObject":
			body.collision_layer |= Collision.RAY_SURFACE
		# The source collision matrix lets kunai pass through one-way platforms.
		if item.get("layer", "") in projectile_layers:
			body.collision_layer |= Collision.PROJECTILE_SURFACE

		if body is DoorPart:
			var piece: Dictionary = door_pieces[item.go]
			body.door = piece.door
			body.collision_layer |= Collision.DAMAGEABLE
			piece.bodies.append(body)
	add_child(body)
	body.name = item.name.validate_node_name()
	if item.get("layer", "") in ceiling_stuck_layers:
		body.collision_layer |= Collision.STUCK_SURFACE
	body.set_meta("source_layer", item.get("layer", ""))
	body.set_meta("source_go", item.get("go", -1))
	body.set_meta("climbable", item.get("layer", "") not in ["HardWall", "Platform"])
	body.transform = Assets.matrix(item.transform)
	match item.kind:
		"BoxCollider2D":
			_rectangle(
				body,
				Rect2(Assets.vec(item.offset) - Assets.vec(item.size) / 2.0, Assets.vec(item.size)),
				item.one_way
			)
		"CircleCollider2D":
			var shape := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = item.radius
			shape.shape = circle
			shape.position = Assets.vec(item.offset)
			body.add_child(shape)
		"PolygonCollider2D":
			for points: Array in item.paths:
				if points.size() < 3:
					continue
				var polygon := CollisionPolygon2D.new()
				var vertices := PackedVector2Array()
				for point: Array in points:
					vertices.append(Assets.vec(point))
				polygon.polygon = vertices
				# Unity paths can contain holes; edge mode preserves their empty interiors.
				polygon.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
				polygon.position = Assets.vec(item.offset)
				polygon.one_way_collision = item.one_way
				body.add_child(polygon)
		"grid":
			var rows: Dictionary = {}
			for cell: Array in item.cells:
				if not rows.has(cell[1]):
					rows[cell[1]] = []
				rows[cell[1]].append(int(cell[0]))
			for y: float in rows:
				var xs: Array = rows[y]
				xs.sort()
				var start: int = xs[0]
				var previous := start
				for i in range(1, xs.size() + 1):
					if i == xs.size() or int(xs[i]) > previous + 1:
						_rectangle(
							body,
							Rect2(
								start * 16.0, -(y + 1.0) * 16.0, (previous - start + 1) * 16.0, 16.0
							),
							item.one_way
						)
						if i < xs.size():
							start = int(xs[i])
					if i < xs.size():
						previous = int(xs[i])
	solid_count += 1
	return body


func _rectangle(body: CollisionObject2D, box: Rect2, one_way: bool) -> void:
	if box.size.x <= 0 or box.size.y <= 0:
		return
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = box.size
	shape.shape = rectangle
	shape.position = box.get_center()
	shape.one_way_collision = one_way
	body.add_child(shape)
