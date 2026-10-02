extends SceneTree
## Bow's nested door sequence retains both waits and finishes zero-time movement.

var lab: Node
var bow: Node
var combat: RefCounted
var door: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func await_phase(expected: String, limit := 180) -> void:
	for frame in limit:
		if combat.door_action.phase == expected:
			return
		await frames(1)
	assert(false, "Expected bow door phase %s, got %s" % [expected, combat.door_action.phase])


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	var guard: Node
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if int(enemy.data.go) == 3454:
			bow = enemy
		elif int(enemy.data.go) == 3214:
			guard = enemy
	for node: Node in lab.stage.get_children():
		if node.has_method("receive_enemy_damage") and int(node.data.go) == 3459:
			door = node
	assert(bow != null and guard != null and door != null)
	await frames(20)
	# Place the source bow at the source guard's feet to exercise the existing
	# factory door; neither the playable spawn nor door data is changed.
	bow.position = (
		guard.patrol._feet()
		- bow.body_shape.position
		- Vector2(0, bow.body_shape.shape.size.y * 0.5)
	)
	bow.velocity = Vector2.ZERO
	for enemy: Node in lab.stage.enemies:
		if enemy != bow:
			enemy.set_physics_process(false)
	combat = bow.bow_combat
	combat.leash_point = combat._ground_point()
	lab.player.set_physics_process(false)
	lab.player.position = bow.position + Vector2(-400, 0)
	combat.target = lab.player
	assert(combat.settings.door.damage == 10.0)
	assert(not combat.settings.door.chase_skip_ready)
	assert(not combat.settings.door.chase_skip_confirm)
	assert(combat.door_action.kick_sound.is_empty())
	combat.acquired = true
	combat._enter_route("chase", lab.player.position)
	await await_phase("ready")
	assert(bow.motion == "AttackReady:1")
	assert(not door.broken and not door.targetable)
	await frames(8)
	assert(not door.broken)
	await await_phase("confirm")
	assert(bow.motion == "AttackConfirm:1")
	await frames(10)
	assert(not door.broken, "Bow retains its full confirmation wait")
	await await_phase("attack")
	assert(door.broken and door.enemy_damage == 10.0)
	assert(bow.motion == "Attack:1")
	assert(bow.knockback.is_empty(), "Zero-duration attack movement cannot remain active")
	assert(not lab.stage.audio.last_selection.has("rifle_kick"))
	await await_phase("post")
	# This route helper never exits AttackState, so its Index=1 post transition
	# differs from normal melee, which resets Index=0 before entering Post.
	assert(bow.motion == "AttackPost:1")
	await await_phase("")
	await frames(2)
	assert(combat.state in ["ready", "confirm"], "The cleared door must restore combat")
	assert(door.enemy_damage == 10.0)
	lab.queue_free()
	await process_frame
	print("BOW_DOOR_PASS")
	quit()
