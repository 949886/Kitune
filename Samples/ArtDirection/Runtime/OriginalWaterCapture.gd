extends Node
## Independent source water view; mirrors visual state without copying gameplay.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Water = preload("res://Samples/ArtDirection/Runtime/OriginalWater.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const SceneProjection = preload("res://Samples/ArtDirection/Runtime/OriginalSceneProjection.gd")
const Lighting = preload("res://Samples/ArtDirection/Runtime/OriginalLighting.gd")
const Particles = preload("res://Samples/ArtDirection/Runtime/OriginalWaterParticles.gd")
const Projectiles = preload("res://Samples/ArtDirection/Runtime/OriginalWaterProjectiles.gd")
const SortingCapture = preload("res://Samples/ArtDirection/Runtime/OriginalSortingCapture.gd")

var viewport := SubViewport.new()
var camera := Camera2D.new()
var projection := SceneProjection.new()
var lighting := Lighting.new()
var particles := Particles.new()
var projectiles := Projectiles.new()
var sorting_capture := SortingCapture.new()
var stage_pairs: Array[Dictionary] = []
var actor_pairs: Array[Dictionary] = []
var line_pairs: Array[Dictionary] = []
var marker_pairs: Array[Dictionary] = []
var surfaces: Array[Node2D] = []
var main_camera: Camera2D
var view_size := Vector2.ZERO
var settings: Dictionary


func configure(stage: Node2D, actor: Node2D, gameplay_camera: Camera2D) -> void:
	settings = Water.source_settings()
	assert(settings.feature.textureFormat == 0 and not settings.feature.useDepth)
	assert(
		settings.feature.updateEveryFrame and int(settings.feature.layerMask.m_Bits) == 0xffffffff
	)
	main_camera = gameplay_camera
	process_priority = 450
	viewport.size = Vector2i(settings.feature.resolution.x, settings.feature.resolution.y)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Nest under the game viewport so the reflection renders before its consumer.
	add_child(viewport)
	viewport.add_child(projection)
	var lens: Dictionary = settings.camera
	projection.configure(
		{
			"distance": -float(lens.offset.y),
			"lens": {"NearClipPlane": lens.near, "FarClipPlane": lens.far}
		}
	)
	viewport.add_child(lighting)
	lighting.configure(stage.data, projection, true, stage.lighting.runtime_lights)
	viewport.add_child(sorting_capture)
	sorting_capture.configure(stage.sort_depth)
	viewport.add_child(particles)
	particles.configure(stage, lighting)
	viewport.add_child(projectiles)
	projectiles.configure(stage, lighting)
	var height := (
		2.0
		* projection.distance
		* tan(deg_to_rad(lens.fov) * 0.5)
		* float(settings.pixels_per_unit)
	)
	var aspect := float(lens.target_size[0]) / float(lens.target_size[1])
	view_size = Vector2(height * aspect, height)
	camera.zoom = Vector2(viewport.size) / view_size
	viewport.add_child(camera)

	for original: Node2D in stage.visual_instances:
		if original.is_water:
			surfaces.append(original)
			original.material.set_shader_parameter("water_texture", viewport.get_texture())
			continue
		var copy := Visual.new()
		copy.configure(original.data)
		lighting.apply_to(copy, original.data)
		var plane: Node2D = projection.parent_for(original.data.get("spatial", {}))
		if plane != null:
			plane.add_child(copy)
		else:
			viewport.add_child(copy)
		projection.register_tilted(copy, original.data.get("spatial", {}))
		copy.set_process(false)
		stage_pairs.append({"source": original, "copy": copy})

	for enemy: Node in stage.enemies:
		if enemy.rifle_combat.cues == null:
			continue
		for original: Line2D in enemy.rifle_combat.cues.lines.values():
			var copy := original.duplicate() as Line2D
			copy.material = original.material.duplicate()
			copy.material.set_shader_parameter("linear_framebuffer", false)
			viewport.add_child(copy)
			line_pairs.append({"source": original, "copy": copy})

	var marker: Node = actor.targeting.presentation
	if is_instance_valid(marker):
		for original: Node2D in marker.visuals:
			var copy := Visual.new()
			copy.configure(original.data)
			lighting.apply_to(copy, original.data)
			viewport.add_child(copy)
			marker_pairs.append({"source": original, "copy": copy})
		var copy := marker.line.duplicate() as Line2D
		copy.material = marker.line.material.duplicate()
		copy.material.set_shader_parameter("linear_framebuffer", false)
		viewport.add_child(copy)
		line_pairs.append({"source": marker.line, "copy": copy, "target_marker": true})

	var gamepad_aim: Node = actor.targeting.gamepad_aim
	if is_instance_valid(gamepad_aim):
		var original: Node2D = gamepad_aim.pointer
		var copy := Visual.new()
		copy.configure(original.data)
		lighting.apply_to(copy, original.data)
		viewport.add_child(copy)
		marker_pairs.append({"source": original, "copy": copy})
		var line := gamepad_aim.line.duplicate() as Line2D
		line.material = gamepad_aim.line.material.duplicate()
		line.material.set_shader_parameter("linear_framebuffer", false)
		viewport.add_child(line)
		line_pairs.append({"source": gamepad_aim.line, "copy": line, "target_marker": true})

	for original: Sprite2D in [actor.sprite, actor.projectile]:
		var copy := Sprite2D.new()
		copy.texture_filter = original.texture_filter
		viewport.add_child(copy)
		if original == actor.sprite:
			actor.sprite.apply_material(copy, lighting)
		elif original == actor.projectile:
			actor.projectile.apply_material(copy, lighting)
		actor_pairs.append({"source": original, "copy": copy, "actor": actor})
	_physics_process(0.0)
	_process(0.0)


func _physics_process(_delta: float) -> void:
	# WaterCameraController follows only the physical main camera's X; Y/Z are
	# the serialized offset. FixedUpdate reads the main camera before its next
	# render-frame follow update; preserve that timing instead of chasing it twice.
	var center := main_camera.get_screen_center_position()
	camera.position = Vector2(
		center.x, -float(settings.camera.offset.x) * float(settings.pixels_per_unit)
	)


func _process(_delta: float) -> void:
	camera.force_update_scroll()
	projection.update_center(camera.position)
	lighting._process(0.0)
	# Emitters run at priority 430; copy their completed frame, including hit-stop.
	particles.sync()
	# TrailRenderer completes its samples at priority 440, before this capture.
	projectiles.sync()
	var center := main_camera.get_screen_center_position()
	for surface: Node2D in surfaces:
		# The water quad is a child of the source WaterCamera, so its X follows
		# the same fixed-step pose even when the main camera has advanced already.
		var parent := surface.get_parent() as Node2D
		parent.position.x = (center.x * (1.0 - parent.scale.x) + camera.position.x * parent.scale.x)
		surface.material.set_shader_parameter(
			"water_camera_x", center.x / float(settings.pixels_per_unit)
		)
	for pair: Dictionary in stage_pairs:
		pair.copy.set_animation_sprite(pair.source.current_sprite)
		pair.copy.transform = pair.source.transform
		pair.copy.modulate = pair.source.modulate
		pair.copy.self_modulate = pair.source.self_modulate
		pair.copy.z_index = pair.source.z_index
		pair.copy.visible = pair.source.is_visible_in_tree()
	for pair: Dictionary in line_pairs:
		pair.copy.global_transform = pair.source.global_transform
		pair.copy.points = pair.source.points
		pair.copy.visible = pair.source.is_visible_in_tree()
		var parameter := "endpoint_depth" if pair.get("target_marker", false) else "material_tint"
		pair.copy.material.set_shader_parameter(
			parameter, pair.source.material.get_shader_parameter(parameter)
		)
	for pair: Dictionary in marker_pairs:
		pair.copy.global_transform = pair.source.global_transform
		pair.copy.modulate = pair.source.modulate
		pair.copy.z_index = pair.source.z_index
		pair.copy.visible = pair.source.is_visible_in_tree()
	for pair: Dictionary in actor_pairs:
		var original: Sprite2D = pair.source
		var copy: Sprite2D = pair.copy
		copy.texture = original.texture
		copy.centered = original.centered
		copy.offset = original.offset
		copy.transform = original.global_transform
		copy.modulate = original.modulate * pair.actor.modulate
		copy.flip_h = original.flip_h
		copy.flip_v = original.flip_v
		copy.z_index = original.z_index + (pair.actor.z_index if original.z_as_relative else 0)
		copy.visible = original.is_visible_in_tree()
		if original == pair.actor.sprite:
			copy.material.set_shader_parameter(
				"inner_outline_alpha", original.material.get_shader_parameter("inner_outline_alpha")
			)
		elif original == pair.actor.projectile:
			copy.material.set_shader_parameter(
				"hit_blend", original.material.get_shader_parameter("hit_blend")
			)
