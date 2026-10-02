extends RefCounted
## EnemyShurikenComponent and EnemyCollision's directional teleport placement.
## Positions inside this solver use Unity units and Y-up, matching source formulas.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const UNITS := 16.0
const SKIN := 0.015
const EDGE_CHECK := 0.06
const MAX_WEAK_POINTS := 3
const DEFAULT_RAY_MASK := Collision.SIGHT_SURFACE | Collision.ONE_WAY

var actor: CharacterBody2D
var weak_points := 0
var reset_time := 0.0


func update(delta: float) -> void:
	if not actor.is_targetable:
		actor.weakpoint_presentation.step(delta)
		return
	if reset_time > 0.0:
		reset_time -= delta
	else:
		weak_points = 0
		actor.weakpoint_presentation.reset()
	actor.weakpoint_presentation.step(delta)


func attach(player: Node) -> bool:
	if actor.dead or not actor.data.kunai.canShurikenHit:
		return false
	actor.receive_study_hit(
		{"Damage": player.combat.ShurikenDamage, "kind": "kunai_stuck", "source_actor": player}, 0.0
	)
	return true


func dash(player: Node) -> void:
	if not actor.data.kunai.ignore_weak_point:
		weak_points = mini(MAX_WEAK_POINTS, weak_points + 1)
		reset_time = float(player.combat.ShurikenStackDisappearTime)
		actor.weakpoint_presentation.hit(weak_points)
		# Native RequestWeakPoint notifies before dash damage. Merely attaching
		# a kunai does not raise this event, and ignored weak points do not either.
		actor.bow_combat.weak_point_changed(player)
		actor.bomb_combat.weak_point_changed(player)
	actor.receive_study_hit(
		{"Damage": player.combat.ShurikenDashDamage, "kind": "kunai_dash", "source_actor": player},
		0.0
	)


func attachment_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(actor.facing, 1.0), 0.0, actor.global_position)


func destination(player: Node) -> Vector2:
	var center := _unity(actor.global_position + actor.body_shape.position)
	var offset := float(player.combat.WeakPointAttackInfo.Offset[weak_points])
	return _destination(player, center, offset)


func weak_attack_path(player: Node) -> Dictionary:
	# DashAttack starts toward the height-aligned enemy center, then passes a
	# copy through CheckShurikenOffsetPosition for the separate recovery segment.
	var center: Vector2 = actor.global_position + actor.body_shape.position
	var height_difference := absf(actor.body_shape.shape.size.y - player.body_size.y)
	var approach := center + Vector2.DOWN * height_difference * 0.5
	var movement: Dictionary = player.combat.WeakPointAttackInfo.AttackMovementInfo
	var recovery := _destination(player, _unity(approach), float(movement.Distance))
	return {"approach": approach, "recovery": recovery, "grounded": _check_below(player, recovery)}


func _check_below(player: Node, center: Vector2) -> bool:
	# PlayerCollision2D.CheckBelow(pos) probes the two full collider corners.
	var feet: Vector2 = center + Vector2.DOWN * player.body_size.y * 0.5
	var left: Vector2 = feet + Vector2.LEFT * player.body_size.x * 0.5
	var right: Vector2 = feet + Vector2.RIGHT * player.body_size.x * 0.5
	var depth := Vector2.DOWN * 0.0165 * UNITS
	return (
		not _ray(_unity(left), _unity(left + depth)).is_empty()
		or not _ray(_unity(right), _unity(right + depth)).is_empty()
	)


func _destination(player: Node, initial_center: Vector2, offset: float) -> Vector2:
	var center := _unity(actor.global_position + actor.body_shape.position)
	var feet := center + Vector2(0, -actor.body_shape.shape.size.y / UNITS * 0.5)
	var player_center := _unity(player.global_position + player.body_shape.position)
	var player_size: Vector2 = player.body_size / UNITS
	var player_feet := player_center.y - player_size.y * 0.5
	var direction := initial_center - player_center
	var side := 1.0 if direction.x >= 0.0 else -1.0
	var end := initial_center
	if absf(player_feet - feet.y) < 1.0:
		end = feet + Vector2(side * offset, 0)
		end = _ground_edge(end, feet, side, offset)
		end += Vector2(-side * player_size.x * 0.5, player_size.y * 0.5)
	else:
		var normalized := direction.normalized()
		var hit := _ray(center, center + normalized * offset)
		var angle := 180.0 + rad_to_deg(direction.angle())
		if _in_sector(angle, 90.0):
			if not hit.is_empty() or center.y + normalized.y * offset > feet.y:
				if not hit.is_empty():
					end = _unity(hit.position)
				end.y = feet.y
				offset = absf(center.x - end.x)
			end = _ground_edge(end, feet, side, offset)
			end += Vector2(-side * player_size.x * 0.5, player_size.y * 0.5)
		elif _in_sector(angle, -90.0):
			end = _unity(hit.position) if not hit.is_empty() else center + normalized * offset
			end += Vector2(-side * player_size.x * 0.5, -player_size.y * 0.5)
		else:
			if not hit.is_empty() and _unity(hit.position).y > end.y:
				end = _unity(hit.position)
				end.y = feet.y
			elif direction.y < 0.0:
				end = feet + Vector2(side * offset, 0)
			else:
				end = center + normalized * offset
			end = _ground_edge(end, feet, side, offset)
			end += Vector2(-side * player_size.x * 0.5, player_size.y * 0.5)
	return _pixels(end)


func _ground_edge(end: Vector2, feet: Vector2, side: float, offset: float) -> Vector2:
	var edge := feet + Vector2(side * actor.body_shape.shape.size.x / UNITS * 0.5, 0)
	var ahead := edge + Vector2(side * absf(offset), 0)
	var wall := _ray(edge, ahead, Collision.STATIC_SURFACE)
	if not wall.is_empty():
		ahead = _unity(wall.position) - Vector2(side * SKIN, 0)
		end.x = ahead.x
	var ground := _ray(ahead, ahead + Vector2(0, -EDGE_CHECK))
	if ground.is_empty():
		ahead.y -= EDGE_CHECK
		var ledge := _ray(ahead, ahead - Vector2(side * absf(feet.x - ahead.x), 0))
		if not ledge.is_empty():
			end.x = _unity(ledge.position).x
	else:
		end.x = _unity(ground.position).x
	return end


func _ray(from: Vector2, to: Vector2, mask := DEFAULT_RAY_MASK) -> Dictionary:
	# Native Default includes interactive walls; its separate Static wall probe
	# does not. Physical solidity alone also includes unrelated doors/objects.
	var query := PhysicsRayQueryParameters2D.create(_pixels(from), _pixels(to), mask)
	# Physics2DSettings enables QueriesStartInColliders in the shipped build.
	query.hit_from_inside = true
	return actor.get_world_2d().direct_space_state.intersect_ray(query)


func _in_sector(angle: float, center: float) -> bool:
	return absf(wrapf(angle - center, -180.0, 180.0)) <= 60.0


func _unity(value: Vector2) -> Vector2:
	return Vector2(value.x, -value.y) / UNITS


func _pixels(value: Vector2) -> Vector2:
	return Vector2(value.x, -value.y) * UNITS
