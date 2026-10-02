extends RefCounted
## EnemyRunAwayPattern selects geometry, then applies shared enemy separation.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var combat_ref: WeakRef
var combat: RefCounted:
	get:
		return combat_ref.get_ref()
var alternate_side := false


func destination() -> Vector2:
	var actor: CharacterBody2D = combat.actor
	var navigation: RefCounted = actor.patrol.navigation
	var start: Vector2 = combat._ground_point()
	var player_cell: Vector2 = navigation.world_center(navigation.nearest(combat.target.position))
	var side := 1.0 if start.x >= player_cell.x else -1.0
	var distance: float = float(actor.data.profile.RunAwayDistance) * actor.PIXELS_PER_UNIT
	var offset: float = float(actor.data.profile.RunAwayOffset) * actor.PIXELS_PER_UNIT
	var end := _candidate(
		start, start + Vector2(side * distance, 0), side, distance, -side * offset, offset
	)
	alternate_side = (
		absf(end.x - start.x)
		< float(combat.settings.retreat.minimum_distance) * actor.PIXELS_PER_UNIT
	)
	if alternate_side:
		var target_feet: Vector2 = combat.target.position + combat.target.body_shape.position
		target_feet.y += combat.target.body_shape.shape.size.y * 0.5
		end.x = target_feet.x - side * distance
		# The original alternate branch keeps -side for its wall offset too;
		# do not reverse that sign a second time to make the result look symmetric.
		end = _candidate(start, end, -side, distance, -side * offset, offset)
	end.y = actor.patrol._feet().y
	var centers: Array[Vector2] = []
	for enemy: Node in actor.get_parent().enemies:
		if not is_instance_valid(enemy) or not enemy.source_active():
			continue
		centers.append(enemy.position + enemy.body_shape.position)
	return navigation.separation.choose(
		navigation,
		end,
		centers,
		float(combat.settings.retreat.separation_radius),
		int(combat.settings.retreat.search_cells)
	)


func _candidate(
	start: Vector2, end: Vector2, side: float, distance: float, wall_offset: float, offset: float
) -> Vector2:
	var edge: Variant = _edge_point(side, distance)
	if edge != null:
		end.x = float(edge) + wall_offset
	end = _ground_path(start, end, offset)
	var leash: float = float(combat.actor.data.profile.LeashRange) * combat.actor.PIXELS_PER_UNIT
	if leash > 0.0:
		end.x = clampf(end.x, combat.leash_point.x - leash, combat.leash_point.x + leash)
	return end


func _edge_point(side: float, distance: float) -> Variant:
	var actor: CharacterBody2D = combat.actor
	var feet: Vector2 = actor.patrol._feet()
	var edge := feet + Vector2(side * actor.body_shape.shape.size.x * 0.5, 0)
	var ahead := edge + Vector2(side * absf(distance), 0)
	var result: Variant = null
	var wall: Dictionary = combat._ray(edge, ahead, Collision.STATIC_SURFACE)
	if not wall.is_empty():
		ahead = wall.position - Vector2(side * actor.patrol.SKIN, 0)
		result = ahead.x
	var check: float = actor.patrol.EDGE_CHECK
	var mask := Collision.STATIC_SURFACE | Collision.SIGHT_SURFACE
	var below: Dictionary = combat._ray(ahead, ahead + Vector2(0, check), mask)
	if below.is_empty():
		ahead.y += check
		var ledge: Dictionary = combat._ray(
			ahead, ahead - Vector2(side * absf(feet.x - ahead.x), 0), mask
		)
		if not ledge.is_empty():
			result = ledge.position.x
	else:
		result = below.position.x
	return result


func _ground_path(start: Vector2, end: Vector2, offset: float) -> Vector2:
	var navigation: RefCounted = combat.actor.patrol.navigation
	var side := 1.0 if end.x >= start.x else -1.0
	var steps := int(absf(end.x - start.x) / navigation.PIXELS_PER_UNIT)
	var result := start
	for index in range(steps + 1):
		var point := start + Vector2(side * index * navigation.PIXELS_PER_UNIT, 0)
		if not navigation.ground.has(navigation.world_cell(point)):
			result.x = point.x - side * offset
			break
		result = point
	return result
