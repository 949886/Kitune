extends SceneTree
## Native path-node proximity and a real factory guard's group-triggered move.

const Navigation = preload("res://Samples/ArtDirection/Runtime/OriginalNavigation.gd")
const Positioning = preload("res://Samples/ArtDirection/Runtime/OriginalRangedPositioning.gd")

var lab: Node
var rifle: Node
var neighbour: Node
var combat: RefCounted


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func navigation_cases() -> void:
	var navigation := Navigation.new()
	var cells: Array = []
	for x in 12:
		cells.append([x, 0])
	navigation.configure(
		{
			"grid": {"transform": [1, 0, 0, 1, 0, 0]},
			"cell_size": [1, 1],
			"ground": [[0, 0]],
			"non_wall": cells,
			"walls": []
		}
	)
	var start := Vector2i.ZERO
	assert(navigation.path(start, start, true).size() == 1, "Self counts as one nearby enemy")
	assert(navigation.path(start, Vector2i(4, 0), true).size() == 5)
	assert(navigation.path(start, Vector2i(5, 0), true).size() == 6)
	assert(navigation.path(start, Vector2i(4, 0)).is_empty(), "Walking still requires ground")
	navigation.non_wall.erase(Vector2i(2, 0))
	var fallback: Array[Vector2i] = navigation.path(start, Vector2i(11, 0), true)
	assert(fallback == [start, Vector2i(1, 0)], "Source proximity accepts a short failed path")
	assert(navigation.path(Vector2i(0, 4), Vector2i(11, 0), true).size() == 1)


func run() -> void:
	navigation_cases()
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if int(enemy.data.go) == 3213:
			rifle = enemy
		elif int(enemy.data.go) == 3214:
			neighbour = enemy
	await frames(12)
	lab.player.set_physics_process(false)
	rifle.set_physics_process(false)
	neighbour.set_physics_process(false)
	combat = rifle.rifle_combat
	assert(combat.settings.positioning.path_nodes == 5.0)
	assert(combat.settings.positioning.count_threshold == 1)
	assert(lab.stage.navigation.non_wall.size() == 543)
	lab.player.position = (
		rifle.patrol._feet()
		+ Vector2(200, -lab.player.body_shape.shape.size.y * 0.5)
		- lab.player.body_shape.position
	)
	combat.target = lab.player
	combat._enter_ready()
	# The native failed-path fallback can count a far guard on another ledge.
	# This is not a Euclidean radius: preserve the shipped result here too.
	assert(combat.retarget_pending)
	combat.reset()
	combat.retargetable = true

	# Only this fixture moves the second original guard onto the first platform.
	neighbour.position = rifle.position + Vector2(16, 0)
	neighbour.velocity = Vector2.ZERO
	neighbour._sync_visuals()
	await frames(2)
	var members: Array[Node] = [rifle, neighbour]
	assert(Positioning.nearby_count(lab.stage.navigation, rifle, members, 5.0) == 2)
	combat._enter_ready()
	assert(combat.retarget_pending and not combat.retargetable)
	assert(combat.state == "ready" and rifle.motion == "AttackReady:0")
	combat.step(1.0 / 60.0)
	assert(combat.state == "retarget" and not combat.route.is_empty())
	var destination: Vector2 = lab.stage.navigation.world_center(combat.route.back())
	assert(destination.x < rifle.position.x)
	rifle.set_physics_process(true)
	await frames(4)
	assert(is_equal_approx(absf(rifle.velocity.x), float(rifle.data.profile.RunAwaySpeed) * 16.0))
	if DisplayServer.get_name() != "headless":
		lab.camera_rig.set_process(false)
		lab.camera.position = rifle.position + Vector2(60, -20)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/inari_rifle_positioning.png"
		)
	for frame in 240:
		if combat.state == "idle":
			break
		await frames(1)
	assert(combat.state == "idle" and combat.route.is_empty())
	assert(combat._ground_point().is_equal_approx(destination))
	assert(not combat.retargetable)
	rifle.set_physics_process(false)

	# One group execution also queues OTHER ready rifles, rather than only its caller.
	neighbour.position = rifle.position + Vector2(16, 0)
	neighbour.rifle_combat.target = lab.player
	neighbour.rifle_combat._change("ready")
	combat.retargetable = true
	combat.reloaded = true
	combat._enter_ready()
	assert(combat.retarget_pending and neighbour.rifle_combat.retarget_pending)
	assert(combat.state == "ready", "Retarget wins over the reloaded Confirm shortcut")
	combat.reset()
	assert(not combat.retarget_pending and not combat.retargetable)
	combat._change("shot")
	combat._change("post")
	assert(combat.retargetable, "AttackState.Exit permits the next round to reposition")

	# Corpses follow source activeInHierarchy, not health or collision layer.
	neighbour.dead = true
	neighbour.death_time = 0.0
	assert(neighbour.source_active())
	neighbour.death_time = (
		float(neighbour.data.profile.DisappearDelayTime) + float(neighbour.data.corpse_fade_time)
	)
	assert(not neighbour.source_active())
	print("RIFLE_POSITIONING_PASS destination=", destination)
	lab.queue_free()
	await process_frame
	quit()
