extends RefCounted
## Source Teleport overlap search followed by PlayerCollision2D attachment logic.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var source: Dictionary
var search: Dictionary
var settings: Dictionary


func configure(player: CharacterBody2D) -> void:
	actor = player
	source = player.ground_snap.settings
	search = source.jump_corner
	settings = player.climb.settings.teleport


func find_position(center: Vector2, mask: int) -> Dictionary:
	var result := {"center": center, "shifted": false, "wall_direction": Vector2.ZERO}
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = actor.body_shape.shape
	query.collision_mask = mask
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = source.queries_hit_triggers
	var skin: float = actor.ground_snap.skin
	var check := center + Vector2.UP * skin
	query.transform = Transform2D(0.0, check)
	var space := actor.get_world_2d().direct_space_state
	if space.intersect_shape(query, 1).is_empty():
		return result
	for attempt in int(search.teleport_attempts):
		for value: Array in search.search_directions:
			var direction := Assets.vec(value).normalized()
			var candidate: Vector2 = (
				check - direction * attempt * skin * search.teleport_step_multiplier
			)
			query.transform.origin = candidate
			if space.intersect_shape(query, 1).is_empty():
				return {"center": candidate, "shifted": true, "wall_direction": direction}
	# Native search exhaustion still translates to the requested center.
	return result


func apply(center: Vector2, entity_hit: bool) -> void:
	var previous: Vector2 = actor.body_shape.global_position
	var mask := Collision.SOLID | (Collision.ONE_WAY if entity_hit else 0)
	var result := find_position(center, mask)
	actor.global_position = result.center - actor.body_shape.position
	var direction: Vector2 = result.wall_direction
	var displacement: Vector2 = result.center - previous
	if not entity_hit and result.shifted and direction != Vector2.DOWN:
		if direction.x != 0.0:
			if _attach_wall(signf(direction.x), mask):
				return
		else:
			actor.ceiling_hang = true
			actor.ceiling_hang = actor.ceiling.attach(previous)
			if actor.ceiling.wall_fallback:
				return
			# Ceiling holds bypass later moves. Refresh Godot's previous-floor
			# cache at this new pose without running gameplay collision callbacks.
			actor.move_and_slide()
	elif entity_hit:
		var side := 1.0 if direction.x >= 0.0 else -1.0
		var origin: Vector2 = actor.global_position + Vector2(side * actor.body_size.x * 0.5, 0)
		var hit := _ray(
			origin,
			Vector2.RIGHT * side * settings.entity_wall_distance * actor.units,
			Collision.STATIC_SURFACE
		)
		if not hit.is_empty() and hit.collider.get_meta("source_layer", "") != "Door":
			actor.global_position -= (
				direction.normalized() * actor.ground_snap.skin * settings.entity_skin_multiplier
			)
	if direction.y > 0.0:
		actor.ground_snap.snap_to_ground(actor.ground_snap.maximum_distance)
	var facing_x := displacement.x * (-1.0 if actor.ceiling_hang else 1.0)
	actor.facing = 1.0 if facing_x >= 0.0 else -1.0


func _attach_wall(side: float, mask: int) -> bool:
	var top: Vector2 = (
		actor.global_position + Vector2(side * actor.body_size.x * 0.5, -actor.body_size.y)
	)
	var spacing: float = source.horizontal_ray_spacing * actor.units
	for index in int(source.horizontal_ray_count):
		var origin := top + Vector2.DOWN * spacing * index
		var hit := _ray(origin, Vector2.RIGHT * side * actor.body_size.y * 0.5, mask)
		if hit.is_empty():
			continue
		var amount := Vector2(
			(origin.distance_to(hit.position) - actor.ground_snap.skin) * side, spacing * index
		)
		actor.move_source_offset(amount)
		actor.gravity_motion.refresh_ray_origins()
		if hit.collider.get_meta("source_layer", "") == settings.wall_excluded_layer:
			return false
		actor.facing = side
		actor.climbing = true
		return true
	return false


func _ray(origin: Vector2, amount: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(origin, origin + amount, mask)
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = source.queries_hit_triggers
	query.hit_from_inside = source.queries_start_in_colliders
	return actor.get_world_2d().direct_space_state.intersect_ray(query)
