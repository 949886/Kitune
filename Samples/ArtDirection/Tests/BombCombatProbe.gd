extends SceneTree
## Live source bomb acquisition, moving fuse, weak-point interruption and blast mask.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var lab: Node
var bomb: Node
var combat: RefCounted
var explosions := 0
var effect: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func setup() -> void:
	if is_instance_valid(lab):
		lab.queue_free()
		await frames(2)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyBombMan" and int(enemy.data.go) == 3277:
			bomb = enemy
	combat = bomb.bomb_combat
	bomb.set_physics_process(true)
	await frames(20)
	bomb.set_physics_process(false)
	explosions = 0
	effect = null
	combat.exploded.connect(
		func(value: Node):
			explosions += 1
			effect = value
	)
	await frames(2)


func place_player(offset: Vector2) -> void:
	lab.player.position = combat._center() + offset - lab.player.body_shape.position
	lab.player.velocity = Vector2.ZERO


func until(state: String, limit := 300) -> void:
	for frame in limit:
		if combat.state == state:
			return
		await frames(1)
	assert(false, "Bomb failed to enter %s; current=%s" % [state, combat.state])


func run() -> void:
	await setup()
	assert(bomb.ranged_combat == combat and not combat.retargetable)
	assert(combat.settings.chase_path_distance == 1.0)
	assert(combat.attack.AttackCheckInfo.AttackRange == {"x": 11.5, "y": 7.5})
	place_player(Vector2(32, 0))
	await frames(2)
	combat.target = lab.player
	bomb.set_physics_process(true)
	await until("ready")
	assert(not combat.fuse_active)
	await frames(60)
	assert(combat.state == "ready" and explosions == 0)
	await until("confirm")
	assert(combat.fuse_active)
	await frames(60)
	assert(combat.state == "confirm" and explosions == 0)
	for frame in 100:
		if bomb.dead:
			break
		await frames(1)
	assert(bomb.dead and explosions == 1 and lab.player.damage.health == 2)
	assert(is_instance_valid(effect) and effect.position.distance_to(bomb.position) < 0.01)
	assert(bomb.visuals.values().all(func(visual: Node): return not visual.visible))
	combat.explode()
	assert(explosions == 1, "Dead bombs cannot emit a second blast")
	if DisplayServer.get_name() != "headless":
		await frames(12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bomb_combat.png")

	# Chase continues moving on the frame that begins its shortened deadline.
	await setup()
	place_player(Vector2(180, 0))
	bomb.facing = 1.0
	await frames(2)
	combat.target = lab.player
	assert(combat._in_sight() and combat._clear_sight() and not combat._in_attack_range())
	var start: Vector2 = bomb.position
	bomb.set_physics_process(true)
	await until("chase")
	await until("confirm")
	assert(bomb.position.distance_to(start) > 30.0)
	assert(combat.fuse_active and explosions == 0)

	# Inspect the absolute-clock subtraction separately at fixed 60 Hz.
	await setup()
	place_player(Vector2(40, 0))
	await frames(2)
	combat.target = lab.player
	combat._enter_route("chase", lab.player.position)
	var before: float = combat.clock
	var speed: float = combat.step(1.0 / 60.0)
	assert(combat.fuse_active and not combat.confirm_pending)
	assert(absf(speed) == float(bomb.data.profile.f_ChaseSpeed) * 16.0)
	assert(is_equal_approx(combat.deadline, before + 0.075))
	combat.step(1.0 / 60.0)
	assert(not combat.confirm_pending)
	combat.step(1.0 / 60.0)
	assert(not combat.confirm_pending)
	combat.step(1.0 / 60.0)
	assert(combat.confirm_pending and combat.state == "chase")
	combat.step(1.0 / 60.0)
	assert(combat.state == "confirm_entry")
	combat.step(1.0 / 60.0)
	assert(combat.state == "confirm")

	# Leaving the range clears the handle; re-entry creates a new deadline.
	combat.reset()
	combat._enter_route("chase", lab.player.position)
	combat.step(1.0 / 60.0)
	assert(combat.fuse_active)
	place_player(Vector2(200, 0))
	await frames(2)
	combat.step(1.0 / 60.0)
	assert(not combat.fuse_active)
	place_player(Vector2(40, 0))
	await frames(2)
	combat.step(1.0 / 60.0)
	assert(combat.fuse_active and not combat.confirm_pending)

	# Merely sticking a kunai does not request confirmation; its weak-point
	# event does, before the accompanying 50 damage. Lethal damage cancels it.
	await setup()
	place_player(Vector2(150, 0))
	await frames(2)
	assert(bomb.receive_study_kunai(lab.player))
	assert(not combat.confirm_pending and not combat.targeted)
	bomb.kunai.dash(lab.player)
	assert(combat.confirm_pending and combat.targeted and not bomb.dead)
	combat.step(1.0 / 60.0)
	assert(combat.state == "confirm_entry")
	assert(is_equal_approx(combat.deadline - combat.clock, 0.0525))
	combat.weak_point_changed(lab.player)
	assert(not combat.confirm_pending)
	combat.step(1.0 / 60.0)
	combat.step(0.2)
	var confirmation_time: float = combat.elapsed
	combat.weak_point_changed(lab.player)
	assert(not combat.confirm_pending and combat.elapsed == confirmation_time)
	bomb.receive_study_hit({"Damage": 100.0}, 1.0)
	assert(bomb.dead and not combat.confirm_pending and not combat.fuse_active)
	combat.step(5.0)
	assert(explosions == 0)

	# Blast uses an overlap, not line of sight; escaping beyond its authored
	# bounds avoids damage, while a thin ordinary wall does not shield a player.
	await setup()
	place_player(Vector2(150, 0))
	await frames(2)
	combat.explode()
	assert(bomb.dead and lab.player.damage.health == 3)
	await setup()
	place_player(Vector2(40, 0))
	var wall := StaticBody2D.new()
	wall.collision_layer = Collision.SIGHT_SURFACE
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(4, 100)
	collider.shape = box
	wall.add_child(collider)
	lab.stage.add_child(wall)
	wall.position = combat._center() + Vector2(20, 0)
	combat.target = lab.player
	await frames(2)
	assert(not combat._clear_sight())
	combat.explode()
	assert(lab.player.damage.health == 2)

	# The source factory door's chase callback detonates after the nested
	# ready/confirm animations, immediately after its ordinary 10-point hit.
	await setup()
	var guard: Node
	var door: Node
	for enemy: Node in lab.stage.enemies:
		if int(enemy.data.go) == 3214:
			guard = enemy
	for node: Node in lab.stage.get_children():
		if node.has_method("receive_enemy_damage") and int(node.data.go) == 3459:
			door = node
	assert(guard != null and door != null)
	# A higher-health fixture keeps original door colliders active through
	# the initial kick, so the following 100-point blast can be observed.
	door.data = door.data.duplicate(true)
	door.data.health = 1000.0
	bomb.position = (
		guard.patrol._feet()
		- bomb.body_shape.position
		- Vector2(0, bomb.body_shape.shape.size.y * 0.5)
	)
	combat.leash_point = combat._ground_point()
	place_player(Vector2(-400, 0))
	combat.target = lab.player
	combat._enter_route("chase", lab.player.position)
	bomb.set_physics_process(true)
	for frame in 300:
		if combat.door_action.phase == "confirm":
			break
		await frames(1)
	assert(combat.door_action.phase == "confirm" and bomb.motion == "AttackConfirm:1")
	assert(door.enemy_damage == 0.0 and explosions == 0)
	for frame in 160:
		if bomb.dead:
			break
		await frames(1)
	assert(bomb.dead and explosions == 1)
	assert(door.enemy_damage >= 110.0 and door.enemy_damage <= 410.0)
	assert(lab.player.damage.health == 3)
	lab.queue_free()
	await frames(2)
	print("BOMB_COMBAT_PASS")
	quit()
