extends RefCounted
## EnemyPatrolPattern: follow source cells, wait, flip, then traverse back.
## Enemy sight/chase transitions are handled separately from this locomotion.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const PIXELS_PER_UNIT := 16.0
const SKIN := 0.015 * PIXELS_PER_UNIT
const EDGE_CHECK := 0.06 * PIXELS_PER_UNIT

var actor: CharacterBody2D
var navigation: RefCounted
var enabled := false
var initialized := false
var waiting := false
var wait_time := 0.0
var left: Vector2i
var right: Vector2i
var route: Array[Vector2i] = []
var next_cell: Vector2i


func configure(enemy: CharacterBody2D, source_navigation: RefCounted) -> void:
	actor = enemy
	navigation = source_navigation
	enabled = bool(actor.data.scout)


func step(delta: float) -> float:
	if not enabled or navigation.ground.is_empty():
		return 0.0
	if not initialized:
		_reset_endpoints()
		_start_route()
		initialized = true

	if waiting:
		wait_time -= delta
		if wait_time <= 0.0:
			if left == right:
				_reset_endpoints()
			actor.facing *= -1.0
			_start_route()
		return 0.0

	var current: Vector2i = navigation.nearest(_feet())
	if route.is_empty():
		waiting = true
		wait_time = float(actor.data.profile.PatrolWaitTime)
		actor.play_motion("Idle")
		return 0.0
	# CheckPathRoot dequeues at cell arrival or when the previous motion was
	# blocked by the native skin-width check. It intentionally skips a stuck cell.
	if current.x == next_cell.x or absf(actor.get_position_delta().x) <= SKIN:
		next_cell = route.pop_front()
	var direction := 1.0 if next_cell.x >= current.x else -1.0
	actor.facing = direction
	if not _can_move(direction):
		return 0.0
	return direction * float(actor.data.profile.f_PatrolSpeed) * PIXELS_PER_UNIT


func _start_route() -> void:
	waiting = false
	var current: Vector2i = navigation.nearest(_feet())
	route = navigation.path(current, right if actor.facing > 0.0 else left)
	if not route.is_empty():
		next_cell = route.pop_front()
	actor.play_motion("MoveX")


func _reset_endpoints() -> void:
	var distance := int(actor.data.scout_distance)
	right = navigation.nearest(_feet(), distance)
	left = navigation.nearest(_feet(), -distance)
	for direction in [-1.0, 1.0]:
		var edge := _feet() + Vector2(direction * _half_width(), 0.0)
		var hit := _ray(edge, edge + Vector2(direction * distance * PIXELS_PER_UNIT, 0.0))
		if not hit.is_empty():
			if direction > 0.0:
				right = navigation.nearest(hit.position)
			else:
				left = navigation.nearest(hit.position)


func _can_move(direction: float) -> bool:
	var edge := _feet() + Vector2(direction * _half_width(), 0.0)
	var ahead := edge + Vector2(direction * EDGE_CHECK, 0.0)
	return (
		_ray(edge, ahead).is_empty() and not _ray(ahead, ahead + Vector2(0, EDGE_CHECK)).is_empty()
	)


func _feet() -> Vector2:
	var rectangle: RectangleShape2D = actor.body_shape.shape
	return actor.position + actor.body_shape.position + Vector2(0, rectangle.size.y * 0.5)


func _half_width() -> float:
	return actor.body_shape.shape.size.x * 0.5


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, Collision.SOLID | Collision.ONE_WAY)
	return actor.get_world_2d().direct_space_state.intersect_ray(query)
