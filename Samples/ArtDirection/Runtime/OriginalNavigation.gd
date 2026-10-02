extends RefCounted
## Source PathFindingManager cells, neighbour order and A* costs.
## Cells remain Unity Y-up; conversion happens only at the scene boundary.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Separation = preload("res://Samples/ArtDirection/Runtime/OriginalEnemySeparation.gd")
const DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1)
]
const PIXELS_PER_UNIT := 16.0

var ground: Dictionary = {}
var walls: Dictionary = {}
var non_wall: Dictionary = {}
var separation := Separation.new()
var grid := Transform2D.IDENTITY
var cell_size := Vector2.ONE


func configure(source: Dictionary) -> void:
	if source.is_empty():
		return
	grid = Assets.matrix(source.grid.transform)
	cell_size = Assets.vec(source.cell_size)
	for cell: Array in source.ground:
		ground[Vector2i(cell[0], cell[1])] = true
	for cell: Array in source.get("walls", []):
		walls[Vector2i(cell[0], cell[1])] = true
	for cell: Array in source.get("non_wall", source.ground):
		non_wall[Vector2i(cell[0], cell[1])] = true


func nearest(world_position: Vector2, offset_x := 0) -> Vector2i:
	var start := world_cell(world_position)
	start.x += offset_x
	if ground.is_empty() or ground.has(start):
		return start

	# The source breadth-first search checks R,L,U,D, then diagonals. Keeping
	# that order matters when an edge or gap has equally near walkable cells.
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if visited.has(next):
				continue
			if ground.has(next):
				return next
			visited[next] = true
			queue.append(next)
	return start


func world_cell(world_position: Vector2) -> Vector2i:
	var local := grid.affine_inverse() * world_position / PIXELS_PER_UNIT
	return Vector2i(floori(local.x / cell_size.x), floori(-local.y / cell_size.y))


func world_center(cell: Vector2i) -> Vector2:
	var local := (Vector2(cell) + Vector2.ONE * 0.5) * cell_size * PIXELS_PER_UNIT
	return grid * Vector2(local.x, -local.y)


func path(start: Vector2i, destination: Vector2i, nearby_search := false) -> Array[Vector2i]:
	if start == destination and not nearby_search:
		return []
	# NearestEnemies calls FindClosestPathWithoutCollision with wall distance 0.
	# It uses raw collider cells, includes the starting node (even self), allows
	# registered air/slope cells, and accepts the closest fallback on failure.
	var available := non_wall if nearby_search else ground
	var open: Array[Vector2i] = [start]
	var closed: Dictionary = {}
	var parents: Dictionary = {}
	var costs := {start: 0.0}
	var closest := start
	while not open.is_empty():
		open.sort_custom(
			func(a: Vector2i, b: Vector2i):
				return costs[a] + _heuristic(a, destination) < costs[b] + _heuristic(b, destination)
		)
		var cell: Vector2i = open.pop_front()
		if _heuristic(cell, destination) < _heuristic(closest, destination):
			closest = cell
		if cell == destination:
			break
		closed[cell] = true
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if not available.has(next) or closed.has(next):
				continue
			var cost: float = costs[cell] + Vector2(direction).length()
			if not costs.has(next) or cost < float(costs[next]):
				costs[next] = cost
				parents[next] = cell
				if next not in open:
					open.append(next)

	# The shipped public PathFinding accepts the best path only if its final
	# X matches the requested target; an unreachable separate ledge stays idle.
	var result: Array[Vector2i] = []
	if not nearby_search and closest.x != destination.x:
		return result
	result.append(closest)
	while parents.has(closest):
		closest = parents[closest]
		result.push_front(closest)
	return result


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))
