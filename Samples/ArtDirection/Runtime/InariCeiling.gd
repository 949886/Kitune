extends RefCounted
## PlayerCollision2D's rotated ceiling body and ordered TrySnapCeiling probes.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var settings: Dictionary
var wall_fallback := false


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = actor.climb.settings.ceiling


func attach(previous_center: Vector2) -> bool:
	wall_fallback = false
	var displacement_x: float = actor.body_shape.global_position.x - previous_center.x
	# Unity Mathf.Sign(0) chooses the rightward rotation. Its final Flip call
	# also maps zero to +1, rather than simply negating that rotation direction.
	var side := 1.0 if displacement_x >= 0.0 else -1.0
	var degrees: float = settings.rightward_degrees if side > 0 else settings.leftward_degrees
	_set_rotation(deg_to_rad(degrees))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = actor.body_shape.shape
	query.transform = actor.body_shape.global_transform
	query.collision_mask = Collision.STUCK_SURFACE
	query.collide_with_areas = actor.ground_snap.settings.queries_hit_triggers
	query.exclude = [actor.get_rid()]
	if not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		restore_upright(false)
		wall_fallback = _snap_back_to_wall()
		return false

	var angle: float = actor.body_shape.rotation
	var top_center: Vector2 = (
		actor.body_shape.global_position
		- Vector2.RIGHT.rotated(angle) * side * actor.body_size.x * 0.5
	)
	var half_height: float = actor.body_size.y * 0.5
	var distance: float = half_height * settings.probe_extent_scale
	for origin_name: String in settings.origins:
		var origin := top_center
		if origin_name == "bottom":
			origin += Vector2.DOWN.rotated(angle) * half_height
		elif origin_name == "top":
			origin += Vector2.UP.rotated(angle) * half_height
		var hit := _ray(origin, Vector2.UP * distance, Collision.SOLID)
		if hit.is_empty():
			continue
		var travel := origin.distance_to(hit.position)
		if travel != 0.0:
			actor.move_source_offset(Vector2.UP * (travel - actor.ground_snap.skin))
		actor.facing = -1.0 if displacement_x > 0.0 else 1.0
		actor.sprite.facing = actor.facing
		actor.sprite._refresh_frame()
		return true
	restore_upright(false)
	return false


func restore_upright(translate := true) -> void:
	if not is_instance_valid(actor) or actor.body_shape.rotation == 0.0:
		return
	_set_rotation(0.0)
	if translate:
		# ResetClimbCeil restores orientation before its half-height downward Move.
		_release_downward()


func _release_downward() -> void:
	# Expanding the body under a roof temporarily overlaps that roof. Godot's
	# depenetration would add a second downward push before the requested move.
	# Native Move instead casts from the new bottom edge and translates once.
	var source: Dictionary = actor.ground_snap.settings
	var distance: float = actor.body_size.y * settings.release_height_scale
	var ray_distance: float = distance + source.jump_corner.ray_padding * actor.units
	var bottom: Vector2 = actor.global_position - Vector2.RIGHT * actor.body_size.x * 0.5
	var landed := false
	for index in int(source.jump_corner.vertical_ray_count):
		var origin: Vector2 = (
			bottom + Vector2.RIGHT * index * source.jump_corner.vertical_ray_spacing * actor.units
		)
		var hit := _ray(origin, Vector2.DOWN * ray_distance, Collision.SOLID | Collision.ONE_WAY)
		if hit.is_empty():
			continue
		var travel := origin.distance_to(hit.position)
		if travel == 0.0 and hit.collider.collision_layer & Collision.ONE_WAY:
			continue
		distance = travel - actor.ground_snap.skin if travel > 0 else 0.0
		ray_distance = travel + actor.ground_snap.skin
		landed = true
	actor.global_position.y += distance
	var retained: Vector2 = actor.velocity
	actor.velocity = Vector2.ZERO
	actor.move_and_slide()
	actor.enemy_contact.after_move(
		Vector2.ZERO, actor.get_physics_process_delta_time() * actor.source_time_scale
	)
	actor.velocity = retained
	if landed:
		actor.source_touched_floor = true
		actor.velocity.y = 0.0


func _set_rotation(angle: float) -> void:
	actor.body_shape.rotation = angle
	actor.sprite.body_rotation = angle
	actor.sprite._refresh_frame()


func _snap_back_to_wall() -> bool:
	var distance: float = actor.body_size.y * 0.5 * settings.probe_extent_scale
	for side in [1.0, -1.0]:
		var origin: Vector2 = actor.global_position + Vector2(side * actor.body_size.x * 0.5, 0)
		var hit := _ray(origin, Vector2.RIGHT * side * distance, Collision.STATIC_SURFACE)
		if hit.is_empty() or hit.collider.get_meta("source_layer", "") == "Door":
			continue
		actor.move_source_offset(hit.position - origin)
		return true
	return false


func _ray(origin: Vector2, amount: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(origin, origin + amount, mask)
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = actor.ground_snap.settings.queries_hit_triggers
	query.hit_from_inside = actor.ground_snap.settings.queries_start_in_colliders
	return actor.get_world_2d().direct_space_state.intersect_ray(query)
