extends SceneTree
## Exercise native idle delay, return animation, ground route and reacquisition.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var rifle: Node
var combat: RefCounted


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func wait_state(expected: String, limit := 900) -> void:
	for frame in limit:
		if combat.state == expected:
			return
		await frames(1)
	assert(false, "Expected %s, got %s at %s" % [expected, combat.state, rifle.position])


func place_target(offset: Vector2) -> void:
	lab.player.position = (
		rifle.position + rifle.body_shape.position + offset - lab.player.body_shape.position
	)
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
	assert(combat._at_leash_point())
	assert(combat.leash_point == combat._ground_point())
	assert(combat.settings.arrival_distance == 0.5)
	assert(float(rifle.data.profile.LeashWaitTime) == 3.0)
	place_target(Vector2(200, 0))
	combat.target = lab.player
	await wait_state("ready")
	# Lose a genuinely acquired player, then displace the enemy along its source
	# floor. This isolates return behavior from retreat's separate route decisions.
	place_target(Vector2(0, -1600))
	await wait_state("idle")
	rifle.position.x += 128.0
	rifle.velocity = Vector2.ZERO
	var idle_position: Vector2 = rifle.position
	await frames(170)
	assert(combat.state == "idle")
	assert(absf(rifle.position.x - idle_position.x) < 0.25)
	await wait_state("leash_ready", 20)
	assert(not combat.acquired)
	assert(rifle.motion == "RunReady:0")
	var preparation := Engine.get_physics_frames()
	await wait_state("leash_back", 30)
	assert(Engine.get_physics_frames() - preparation >= 16)
	assert(rifle.motion == "MoveX:0")
	await frames(4)
	assert(is_equal_approx(absf(rifle.velocity.x), float(rifle.data.profile.f_PatrolSpeed) * 16.0))
	await wait_state("idle")
	assert(combat._at_leash_point(), "Return must reach the original ground cell")
	await frames(190)
	assert(combat.state == "idle", "An unalerted enemy at home must not repeatedly return")
	assert(not combat.acquired)

	# Repeat a return with a visible player behind an occluder. Removal must
	# reacquire immediately, before the enemy reaches its original cell.
	rifle.position.x += 160.0
	combat.acquired = true
	combat._change("idle")
	await wait_state("leash_back")
	place_target(Vector2(160, 0))
	var wall := StaticBody2D.new()
	wall.collision_layer = Collision.SIGHT_SURFACE
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 200)
	shape.shape = rectangle
	wall.add_child(shape)
	wall.position = combat._center() + Vector2(80, 0)
	lab.stage.add_child(wall)
	await frames(3)
	assert(combat.state == "leash_back" and not combat.acquired)
	wall.queue_free()
	await wait_state("ready", 5)
	assert(combat.acquired)
	assert(not combat._at_leash_point())
	assert(rifle.velocity.x == 0.0)
	assert(combat.route.is_empty(), "Reacquisition must release the return route")
	combat.target = null
	assert(combat.state == "idle" and not combat.acquired and combat.route.is_empty())
	# All five source angle branches must leave Attack even when the authored
	# sprite clip loops. A target above the enemy previously trapped this state.
	place_target(Vector2(0, -1600))
	combat.target = lab.player
	for angle in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		rifle.ranged_presentation.set_aiming(true)
		rifle.ranged_presentation.set_angle(angle)
		combat._enter_shot()
		await wait_state("post", 90)
		assert(combat.rounds == 0)
	combat.target = null

	# The source scout resumes its patrol state after returning; stationary
	# guards remain idle. Use the actual scout and its native floor and speed.
	for enemy: Node in lab.stage.enemies:
		if int(enemy.data.go) == 3215:
			rifle = enemy
	combat = rifle.rifle_combat
	place_target(Vector2(0, -1600))
	combat.target = lab.player
	rifle.position.x += 64.0
	combat.acquired = true
	rifle.patrol.enabled = true
	await wait_state("leash_back")
	await wait_state("idle")
	assert(combat._at_leash_point())
	await frames(12)
	assert(rifle.patrol.initialized)
	assert(rifle.motion == "MoveX")
	assert(is_equal_approx(absf(rifle.velocity.x), float(rifle.data.profile.f_PatrolSpeed) * 16.0))
	print("RIFLE_LEASH_PASS")
	lab.queue_free()
	await process_frame
	quit()
