extends SceneTree
## Original factory door, nested kick timing, retreat flags and cancellation.

var lab: Node
var rifle: Node
var combat: RefCounted
var door: Node
var door_x := 0.0


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func setup() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if int(enemy.data.go) == 3214:
			rifle = enemy
	combat = rifle.rifle_combat
	for node: Node in lab.stage.get_children():
		if node.has_method("receive_enemy_damage") and int(node.data.go) == 3459:
			door = node
	assert(door != null and door.data.health == 1.0)
	door_x = door.pieces[0].bodies[0].position.x
	await frames(12)
	lab.player.set_physics_process(false)
	lab.player.position = rifle.position + Vector2(-400, 0)
	combat.target = lab.player
	assert(combat.settings.door.damage == 10.0)
	assert(not combat.settings.door.chase_skip_ready)
	assert(combat.settings.door.retreat_skip_ready)


func cleanup() -> void:
	lab.queue_free()
	await process_frame
	door = null


func await_phase(expected: String, limit := 180) -> void:
	for frame in limit:
		if combat.door_action.phase == expected:
			return
		await frames(1)
	assert(false, "Expected door phase %s, got %s" % [expected, combat.door_action.phase])


func start_chase() -> void:
	combat.acquired = true
	combat._enter_route("chase", lab.player.position)


func run() -> void:
	await setup()
	start_chase()
	await await_phase("ready")
	assert(rifle.motion == "AttackReady:1")
	assert(not door.broken and not door.targetable and combat.route.is_empty())
	assert(not combat.door_action.try_begin(), "An already claimed door cannot be claimed again")
	if DisplayServer.get_name() != "headless":
		# Isolate the kick for visual inspection; the playable level retains its
		# native camera controller. This affects only this probe's first capture.
		lab.camera_rig.set_process(false)
		lab.camera.position = rifle.position + Vector2(-50, -20)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
	var start: Vector2 = rifle.position
	await frames(12)
	assert(not door.broken and rifle.position.is_equal_approx(start))
	await await_phase("attack", 20)
	assert(door.broken and door.enemy_damage == 10.0)
	assert(rifle.motion == "Attack:1")
	assert(not lab.stage.audio.last_selection.has("rifle_shot"))
	# The original nested chase helper does not invoke the Attack state sound
	# event; only the retreat caller explicitly plays Kick.
	assert(not lab.stage.audio.last_selection.has("rifle_kick"))
	await frames(2)
	for piece: Dictionary in door.pieces:
		for body: Node in piece.bodies:
			assert(body.collision_layer == 0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_rifle_door.png")
	await await_phase("post")
	assert(rifle.motion == "Attack:1", "Missing Index=1 post transition keeps the kick state")
	await await_phase("")
	assert(door.enemy_damage == 10.0)
	await frames(2)
	assert(combat.state in ["ready", "confirm"], "Clear sight after the kick must restore combat")
	await cleanup()

	await setup()
	# Move the original guard close to its original door and let a real nearby
	# player trigger retreat. The native route crosses the door on the left.
	rifle.position.x = door_x + 50.0
	rifle.velocity = Vector2.ZERO
	lab.player.position = rifle.position + Vector2(30, 0)
	combat.retargetable = false
	await await_phase("attack")
	assert(combat.state == "retreat" and door.broken)
	assert(lab.stage.audio.last_selection.has("rifle_kick"))
	assert(lab.stage.audio.groups.rifle_kick == ["Monster_Rifle_Kick.wav"])
	await await_phase("")
	await frames(1)
	assert(combat.state == "idle", "The source clears retreat's route when it kicks")
	await cleanup()

	await setup()
	rifle.position.x = door_x - 60.0
	rifle.velocity = Vector2.ZERO
	lab.player.position = rifle.position + Vector2(0, -1600)
	combat._enter_route("leash_back", combat.leash_point)
	await await_phase("ready")
	await await_phase("confirm")
	assert(not door.broken and rifle.motion == "AttackReady:1")
	await frames(10)
	assert(not door.broken, "The return helper retains its confirm wait")
	await await_phase("attack")
	assert(door.broken)
	await await_phase("")
	await frames(1)
	assert(combat.state == "idle" and combat.route.is_empty())
	await cleanup()

	await setup()
	# Retarget inherits RunAway's kick call and metal exception, but its own
	# helper retains both waits; Rifle.Start only changes the RunAway helper.
	rifle.position.x = door_x + 50.0
	rifle.velocity = Vector2.ZERO
	lab.player.position = rifle.position + Vector2(400, 0)
	combat._enter_retreat("retarget")
	await await_phase("ready")
	assert(lab.stage.audio.last_selection.has("rifle_kick"))
	await await_phase("confirm")
	assert(not door.broken)
	await await_phase("attack")
	assert(door.broken)
	await await_phase("")
	await frames(1)
	assert(combat.state == "idle" and combat.route.is_empty())
	await cleanup()

	await setup()
	start_chase()
	await await_phase("ready")
	rifle.receive_study_hit({"Damage": 10000.0}, 1.0)
	assert(rifle.dead and combat.door_action.phase.is_empty())
	await frames(80)
	assert(not door.broken and door.enemy_damage == 0.0)
	await cleanup()

	await setup()
	# The factory's doors are wooden. Change only the interaction flags in this
	# isolated fixture to cover the native heavy-only exception during retreat.
	door.data = door.data.duplicate(true)
	door.data.interactions = 12
	rifle.position.x = door_x + 28.0
	rifle.facing = -1.0
	rifle.set_physics_process(false)
	await frames(2)
	for route_state in ["retreat", "retarget"]:
		combat._enter_route(route_state, rifle.position - Vector2(100, 0))
		assert(not combat.door_action.try_begin())
	assert(door.targetable and not door.broken)
	await cleanup()
	print("RIFLE_DOOR_PASS")
	quit()
