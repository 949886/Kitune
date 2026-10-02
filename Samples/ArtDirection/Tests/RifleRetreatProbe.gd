extends SceneTree
## Source separation order and real factory retreat paths near the left wall.

const Navigation = preload("res://Samples/ArtDirection/Runtime/OriginalNavigation.gd")

var lab: Node
var rifle: Node
var combat: RefCounted


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	await separation_cases()
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if int(enemy.data.go) == 3213:
			rifle = enemy
	combat = rifle.rifle_combat
	await frames(12)
	lab.player.set_physics_process(false)
	rifle.set_physics_process(false)
	var origin: Vector2 = rifle.position
	assert(lab.stage.navigation.walls.size() == 1714)
	assert(combat.settings.retreat.minimum_distance == 2.0)
	assert(combat.settings.retreat.separation_radius == 3.0)
	assert(combat.settings.retreat.search_cells == 50)
	for sample in [[0.0, false], [-64.0, true]]:
		combat.target = null
		rifle.set_physics_process(false)
		rifle.position = origin + Vector2(float(sample[0]), 0)
		rifle.velocity = Vector2.ZERO
		lab.player.position = rifle.position + Vector2(30, 0)
		await frames(2)
		combat.target = lab.player
		# Exercise close-player retreat after this round's group positioning.
		# Initial crowd-triggered Retarget has its own end-to-end probe.
		combat.retargetable = false
		rifle.set_physics_process(true)
		for frame in 12:
			if combat.state == "retreat":
				break
			await frames(1)
		assert(combat.state == "retreat", "A nearby live player must trigger retreat")
		assert(combat.retreat.alternate_side == bool(sample[1]))
		var start: Vector2 = combat._ground_point()
		var end: Vector2 = lab.stage.navigation.world_center(combat.route.back())
		assert(end.x > start.x if sample[1] else end.x < start.x)
		lab.player.position.y -= 1600.0
		await frames(4)
		assert(
			is_equal_approx(absf(rifle.velocity.x), float(rifle.data.profile.RunAwaySpeed) * 16.0)
		)
		for frame in 240:
			if combat.state == "idle":
				break
			await frames(1)
		assert(combat.state == "idle" and rifle.velocity.x == 0.0)
		assert(
			combat._ground_point().is_equal_approx(end),
			"Retreat must reach its selected ground cell"
		)
		assert(combat.route.is_empty())
		print("RETREAT_ROUTE_PASS alternate=", sample[1], " distance=", end.x - start.x)
	# The native cell walk stops at the first missing ground cell and applies
	# the authored five-unit offset, even when that puts the result behind start.
	var navigation: RefCounted = lab.stage.navigation
	var start: Vector2 = combat._ground_point()
	var gap: Vector2i = navigation.world_cell(start + Vector2(48, 0))
	assert(navigation.ground.has(gap))
	navigation.ground.erase(gap)
	var limited: Vector2 = combat.retreat._ground_path(start, start + Vector2(160, 0), 80)
	navigation.ground[gap] = true
	assert(limited.x == start.x - 32.0)
	print("RIFLE_RETREAT_PASS")
	lab.queue_free()
	await process_frame
	quit()


func separation_cases() -> void:
	var navigation := Navigation.new()
	var cells: Array = []
	for x in range(-10, 11):
		cells.append([x, 0])
	navigation.configure(
		{
			"grid": {"transform": [1, 0, 0, 1, 0, 0]},
			"cell_size": [1, 1],
			"ground": cells,
			"walls": []
		}
	)
	var point := Vector2(8, -8)
	var centers: Array[Vector2] = [point]
	var first: Vector2 = navigation.separation.choose(navigation, point, centers, 3.0, 50)
	assert(first == Vector2(-56, -8), "Native BFS checks the left side first outside the radius")
	var second: Vector2 = navigation.separation.choose(navigation, point, centers, 3.0, 50)
	assert(
		second == Vector2(72, -8), "Same-frame reservations prevent choosing the first point again"
	)
	await frames(1)
	assert(navigation.separation.choose(navigation, point, centers, 3.0, 50) == first)
	await frames(1)
	navigation.walls[Vector2i(-1, 0)] = true
	assert(navigation.separation.choose(navigation, point, centers, 3.0, 50) == second)
	await frames(1)
	navigation.walls[Vector2i(1, 0)] = true
	assert(navigation.separation.choose(navigation, point, centers, 3.0, 50) == point)
	await frames(1)
	navigation.walls.clear()
	assert(navigation.separation.choose(navigation, point, centers, 3.0, 2) == point)
