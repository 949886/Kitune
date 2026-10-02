extends RefCounted
## Nested EnemyCheckDoorPattern; the owning route state resumes after recovery.

signal attack_started

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var combat_ref: WeakRef
var combat: RefCounted:
	get:
		return combat_ref.get_ref()
var door: Node
var phase := ""
var elapsed := 0.0
var skip_confirm := false
var kick_sound := ""


func try_begin() -> bool:
	var actor: CharacterBody2D = combat.actor
	var size: Vector2 = actor.body_shape.shape.size
	var query := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	query.shape = box
	query.transform.origin = combat._center() + Vector2(actor.facing * size.x, 0)
	query.collision_mask = Collision.SIGHT_SURFACE
	for hit: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query):
		var body: Node = hit.collider
		if body.get_meta("source_layer", "") != "InteractiveWall" or not "door" in body:
			continue
		var candidate: Node = body.door
		if not is_instance_valid(candidate) or candidate.broken or not candidate.targetable:
			continue
		if combat.state in ["retreat", "retarget"] and int(candidate.data.interactions) == 12:
			continue
		door = candidate
		door.targetable = false
		combat.route.clear()
		combat.route_index = 0
		var rules: Dictionary = combat.settings.door
		var skip_ready := false
		skip_confirm = false
		if combat.state in ["chase", "retreat"]:
			skip_ready = rules[combat.state + "_skip_ready"]
			skip_confirm = rules[combat.state + "_skip_confirm"]
		# Retarget inherits the RunAway coroutine but owns a separate door
		# helper. Rifle.Start only skips timings on RunAway, not Retarget.
		if combat.state in ["retreat", "retarget"] and not kick_sound.is_empty():
			actor.get_parent().audio.play(kick_sound)
		if not skip_ready:
			_enter("ready", "AttackReady")
		elif not skip_confirm:
			_enter("confirm", "AttackConfirm")
		else:
			_hit()
		return true
	return false


func step(delta: float) -> void:
	elapsed += delta
	if elapsed <= combat.actor.motion_duration:
		return
	match phase:
		"ready":
			if skip_confirm:
				_hit()
			else:
				_enter("confirm", "AttackConfirm")
		"confirm":
			_hit()
		"attack":
			if combat.actor.knockback.is_empty():
				_enter("post", "AttackPost")
		"post":
			combat.actor.play_combat_motion("Chase", 1)
			reset()


func reset() -> void:
	phase = ""
	elapsed = 0.0
	door = null


func _enter(value: String, trigger: String) -> void:
	phase = value
	elapsed = 0.0
	# Missing Animator transitions still reset the native state-machine clock:
	# retain the old pose whenever the current prefab has no matching transition.
	combat.actor.play_combat_motion(trigger, 1)


func _hit() -> void:
	if is_instance_valid(door):
		door.receive_enemy_damage(float(combat.settings.door.damage), combat.actor.facing)
	attack_started.emit()
	if combat.actor.dead:
		return
	# Setting Animator.Index to 1 does not change StateMachine.AttackInfo.
	# The source door helper therefore uses the current attack movement profile.
	combat.actor.apply_attack_movement(combat.attack.AttackMovementInfo)
	_enter("attack", "Attack")
