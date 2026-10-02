extends SceneTree
## Original endpoint replanning, chase-boundary clamp and paused chase restart.

var lab: Node
var rifle: Node
var combat: RefCounted


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func target_offset(offset: Vector2) -> void:
	lab.player.position = rifle.position + offset
	lab.player.velocity = Vector2.ZERO


func run() -> void:
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
	var origin: Vector2 = rifle.position
	var navigation: RefCounted = rifle.patrol.navigation
	var start: Vector2 = combat._ground_point()
	assert(combat.settings.chase_path_fraction == 0.5)
	assert(float(rifle.data.profile.LeashRange) == 25.0)
	target_offset(Vector2(1500, 0))
	combat.target = lab.player
	combat.acquired = true
	# Start with a previously planned short leg, then let the live target move
	# beyond it. Native tuning stays intact, including the 25-unit leash.
	combat._enter_route("chase", start + Vector2(64, 0))
	var previous_end: Vector2i = combat.route.back()
	await frames(8)
	assert(combat.state == "chase" and combat.route.back() == previous_end)
	assert(is_equal_approx(rifle.velocity.x, float(rifle.data.profile.f_ChaseSpeed) * 16.0))
	var replanned := false
	for frame in 100:
		await frames(1)
		assert(combat.state == "chase", "Arriving at an old endpoint must not restart Idle")
		if combat.route.back() != previous_end:
			replanned = true
			break
	assert(replanned)
	var boundary: Vector2 = start + Vector2(float(rifle.data.profile.LeashRange) * 16.0, 0)
	assert(combat.route.back() == navigation.nearest(boundary))
	assert(not combat.chase_preparing, "A running chase must not replay RunReady")
	for frame in 240:
		if combat.state == "idle":
			break
		await frames(1)
	assert(combat.state == "idle" and combat.route.is_empty())
	assert(not combat._inside_leash(combat._ground_point().x))
	assert(absf(combat._ground_point().x - boundary.x) < 0.01)

	combat.target = null
	rifle.position = origin
	rifle.velocity = Vector2.ZERO
	target_offset(Vector2(200, -1600))
	combat.target = lab.player
	combat.acquired = true
	combat._enter_route("chase", start)
	await frames(200)
	assert(combat.state == "chase", "A close but occluded target waits in Chase")
	assert(rifle.motion == "Idle" and rifle.velocity.x == 0.0)
	assert(combat.route.is_empty())
	# Move outside half the original attack width. Restart must wait for the
	# original RunReady state even though its sprite binding is absent here.
	target_offset(Vector2(1500, 0))
	for frame in 5:
		if combat.chase_preparing:
			break
		await frames(1)
	assert(combat.chase_preparing and rifle.motion == "RunReady:0")
	var stopped: Vector2 = rifle.position
	await frames(12)
	assert(combat.chase_preparing and rifle.position.is_equal_approx(stopped))
	for frame in 20:
		if not combat.chase_preparing:
			break
		await frames(1)
	await frames(2)
	assert(rifle.motion == "Chase:0" and rifle.velocity.x > 0.0)
	target_offset(Vector2(200, 0))
	for frame in 5:
		if combat.state == "ready":
			break
		await frames(1)
	assert(combat.state == "ready" and combat.route.is_empty())
	assert(rifle.velocity.x == 0.0)
	print("RIFLE_CHASE_PASS")
	lab.queue_free()
	await process_frame
	quit()
