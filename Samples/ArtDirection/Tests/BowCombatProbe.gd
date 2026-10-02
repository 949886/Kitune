extends SceneTree
## Live bow acquisition, occlusion, private retreat roll, melee fallback and group retarget.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var bow: Node
var combat: RefCounted
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func place_player(offset: Vector2) -> void:
	lab.player.position = combat._center() + offset - lab.player.body_shape.position
	lab.player.velocity = Vector2.ZERO


func until(state: String, limit := 300) -> void:
	for frame in limit:
		if combat.state == state:
			return
		await frames(1)
	assert(false, "Bow failed to enter %s; current=%s" % [state, combat.state])


func seed_roll(retreat: bool) -> void:
	var random := RandomNumberGenerator.new()
	for value in 100:
		random.seed = value
		if (random.randi_range(0, 99) < combat.decision.run_away_weight) == retreat:
			combat.random.seed = value
			return
	assert(false, "Fixture could not select a deterministic original probability branch")


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
		else:
			enemy.set_physics_process(false)
	combat = bow.bow_combat
	assert(bow.ranged_combat == combat and combat.decision.run_away_weight == 80.0)
	assert(not combat.decision.can_alarm and combat.door_action.kick_sound.is_empty())
	bow.bow_attack.arrow_launched.connect(func(_arrow: Node): shots += 1)
	await frames(20)
	place_player(Vector2(140, 0))
	await frames(2)
	combat.target = lab.player
	assert(combat._clear_sight() and combat._in_sight() and not combat._too_close())
	await until("ready")
	assert(bow.bow_attack.active() and bow.bow_attack.attack_index == 0)
	await until("confirm")
	if DisplayServer.get_name() != "headless":
		await frames(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bow_combat.png")
	await until("shot")
	assert(shots == 1)
	await frames(12)
	assert(
		lab.player.damage.health == 2, "An automatically selected bow shot must hit the real player"
	)

	# Occlusion prevents reacquisition after this attack has completed.
	var blocker := StaticBody2D.new()
	blocker.collision_layer = Collision.SIGHT_SURFACE | Collision.ARROW_SURFACE
	blocker.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 100)
	shape.shape = rectangle
	blocker.add_child(shape)
	lab.stage.add_child(blocker)
	blocker.position = combat._center() + Vector2(70, 0)
	await until("idle")
	await frames(100)
	assert(combat.state == "idle" and shots == 1 and not combat._clear_sight())
	blocker.queue_free()
	await frames(2)

	# Force one native integer roll below 80, then pursue the retreating bow.
	combat.target = null
	combat.can_run_away = true
	seed_roll(true)
	place_player(Vector2(32, 0))
	await frames(2)
	combat.target = lab.player
	await until("retreat")
	assert(not combat.can_run_away and not bow.bow_attack.active())
	var retreat_start: Vector2 = bow.position
	var moving := 0
	for frame in 360:
		place_player(Vector2(32, 0))
		await frames(1)
		if combat.state == "retreat" and absf(bow.velocity.x) > 0.0:
			moving += 1
			assert(
				is_equal_approx(absf(bow.velocity.x), float(bow.data.profile.RunAwaySpeed) * 16.0)
			)
		if combat.state == "ready" and bow.bow_attack.attack_index == 1:
			break
	assert(moving > 5 and absf(bow.position.x - retreat_start.x) > 20.0)
	assert(combat.state == "ready" and bow.bow_attack.attack_index == 1)
	assert(
		not combat.can_run_away, "One completed retreat must force a close melee until Post exits"
	)
	await until("post")
	assert(not combat.can_run_away)
	await until("idle")
	assert(combat.can_run_away)

	# A roll in the remaining 20 percent selects melee immediately.
	combat.target = null
	seed_roll(false)
	place_player(Vector2(32, 0))
	await frames(2)
	combat.target = lab.player
	await until("ready")
	assert(bow.bow_attack.attack_index == 1 and not combat.retreat_pending)
	combat.target = null
	await frames(2)
	bow.patrol.enabled = true
	await frames(12)
	assert(
		bow.motion == "MoveX" or bow.patrol.waiting,
		"Clearing combat must return control to the source patrol"
	)
	bow.patrol.enabled = false

	# Group retarget is queued before the close-range roll. Both requests may
	# exist, but the source's first transition wins without starting an attack.
	var neighbour: Node
	for enemy: Node in lab.stage.enemies:
		if enemy.data.kind == "EnemyRifleMan":
			neighbour = enemy
			break
	neighbour.position = (
		bow.position + Vector2(16, 0) + bow.body_shape.position - neighbour.body_shape.position
	)
	neighbour.rifle_combat.state = "ready"
	neighbour.rifle_combat.retargetable = true
	combat.retargetable = true
	combat.can_run_away = true
	# Isolate first-request priority with the original initial ranged index.
	# Clearing a target after cancelled melee now correctly retains AttackIndex.
	bow.bow_attack.attack_index = 0
	seed_roll(true)
	place_player(Vector2(32, 0))
	await frames(2)
	combat.target = lab.player
	await until("ready")
	assert(combat.retarget_pending and combat.retreat_pending)
	assert(neighbour.rifle_combat.retarget_pending)
	await frames(1)
	assert(combat.state == "retarget" and not combat.retreat_pending and not combat.retargetable)
	assert(not combat.can_run_away and not bow.bow_attack.active())
	bow._die(null)
	var count := shots
	await frames(90)
	assert(not bow.bow_attack.active() and shots == count and combat.state == "idle")
	lab.queue_free()
	await process_frame
	print("BOW_COMBAT_PASS shots=", shots, " retreat_frames=", moving)
	quit()
