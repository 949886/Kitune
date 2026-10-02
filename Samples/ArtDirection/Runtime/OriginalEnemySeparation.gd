extends RefCounted
## Native horizontal candidate search, circular blocked cells and frame reservations.

var reserved: Dictionary = {}
var reserved_frame := -1


func choose(
	navigation: RefCounted, point: Vector2, centers: Array[Vector2], radius: float, limit: int
) -> Vector2:
	# Unity shares reservations across all enemies for one Update frame. This
	# port runs AI in physics steps, so reservations share that same tick boundary.
	var frame := Engine.get_physics_frames()
	if reserved_frame != frame:
		reserved_frame = frame
		reserved.clear()
	var radius_cells := ceili(radius / maxf(navigation.cell_size.x, navigation.cell_size.y))
	var blocked := reserved.duplicate()
	for center in centers:
		_stamp(blocked, navigation.world_cell(center), radius_cells)
	var start: Vector2i = navigation.nearest(point)
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var fallback := start
	var closest := INF
	var index := 0
	var distance_squared: float = pow(radius * navigation.PIXELS_PER_UNIT, 2.0)
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if limit >= 0 and absi(cell.x - start.x) > limit:
			continue
		if navigation.ground.has(cell):
			var world: Vector2 = navigation.world_center(cell)
			var nearest_distance := INF
			for center in centers:
				nearest_distance = minf(nearest_distance, world.distance_squared_to(center))
			if not blocked.has(cell) and nearest_distance >= distance_squared:
				_stamp(reserved, cell, radius_cells)
				return world
			# Preserve the source's minimum-distance fallback, even though it may
			# choose a crowded point when every candidate is blocked.
			if nearest_distance < closest:
				closest = nearest_distance
				fallback = cell
		for side in [-1, 1]:
			var next := cell + Vector2i(side, 0)
			if visited.has(next):
				continue
			visited[next] = true
			if not navigation.walls.has(next):
				queue.append(next)
	_stamp(reserved, fallback, radius_cells)
	return navigation.world_center(fallback)


func _stamp(cells: Dictionary, center: Vector2i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				cells[center + Vector2i(x, y)] = true
