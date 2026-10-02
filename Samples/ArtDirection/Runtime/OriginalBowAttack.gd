extends RefCounted
## Bow attack coroutine after the AI has selected ranged or melee: ready, confirm, attack, post.
## Alarm, positioning, retreat selection and chase belong to the surrounding AI state machine.

signal state_changed(value: String)
signal arrow_launched(arrow: Node2D)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var target: CharacterBody2D
var settings: Dictionary
var state := "idle"
var elapsed := 0.0
var attack_index := 0
var attack: Dictionary
var ready_wait := 0.0
var confirm_wait := 0.0
var rotation_wait := 0.0
var rounds := 0
var shot_origin := Vector2.ZERO
var shot_angle := 0.0
var player_checked := false
var wall_damage := 0.0
var pull_sound := 0
var targeting_attack := false
var entry_phase := ""
var flip_direction := 1.0
var animation_angle := 0.0


func configure(enemy: CharacterBody2D) -> void:
	actor = enemy
	if actor.data.kind == "EnemyBowMan":
		var source: Dictionary = Assets.read_json(Assets.ROOT + "bow_combat.json")
		settings = (
			actor.data.bow_binding
			if actor.data.has("bow_binding")
			else source.actors[str(int(actor.data.go))]
		)
		wall_damage = float(source.wall_damage)


func active() -> bool:
	return state != "idle"


func begin(player: CharacterBody2D, index: int) -> void:
	assert(not settings.is_empty() and index in [0, 1])
	if actor.dead:
		return
	target = player
	entry_phase = ""
	attack_index = index
	attack = actor.data.profile.AttackInfoList[index]
	ready_wait = float(attack.AttackCheckInfo.AttackReadyTime)
	var audio: Node = actor.get_parent().audio
	if index == 0:
		pull_sound = audio.play_event("bow_pull", actor)
	else:
		# Source melee starts its sound at Ready, and returns the previous Pull.
		# Ready cancellation itself does not stop Pull in EnemyBowMan.
		audio.stop_event(pull_sound)
		audio.play_event("bow_attack", actor)
	actor.facing = 1.0 if target.position.x >= actor.position.x else -1.0
	actor.ranged_presentation.set_aiming(false)
	_change("ready")
	actor.play_combat_motion("AttackReady", attack_index)


func step(delta: float) -> void:
	if not active():
		return
	if actor.dead or not is_instance_valid(target) or target.dead:
		reset()
		return
	elapsed += delta
	match state:
		"ready":
			if attack_index == 0 and too_close():
				cancel()
			elif _finished():
				if ready_wait > 0.0:
					ready_wait -= delta
					if attack_index == 0:
						_track(delta)
				else:
					_change("confirm")
					confirm_wait = float(attack.AttackCheckInfo.AttackConfirmTime)
					actor.play_combat_motion("AttackConfirm", attack_index)
		"confirm":
			# Unlike the rifle, the bow locks at the end of Ready and waits for
			# the actual confirmation clip, then any additional authored delay.
			if _finished():
				if confirm_wait > 0.0:
					confirm_wait -= delta
				else:
					_enter_attack()
		"attack":
			if not entry_phase.is_empty():
				_step_attack_entry()
			elif not _finished():
				_check_attack_frame()
			elif actor.knockback.is_empty():
				_change("post")
				# AttackState.Exit resets Animator Index to zero before Post enters.
				# This bow has no Post:0 transition, so both attack modes retain
				# their clip while ChangeAnimation restarts the gameplay clock.
				actor.play_combat_motion("AttackPost", 0)
		"post", "cancel":
			if _finished():
				reset()


func _track(delta: float) -> void:
	if rotation_wait > 0.0:
		rotation_wait -= delta
		return
	rotation_wait = float(actor.data.profile.RangeRotationFrame) * delta
	var direction: Vector2 = target.global_position + target.body_shape.position - center()
	var desired := rad_to_deg(atan2(-direction.y, direction.x * actor.facing))
	var current: float = actor.ranged_presentation.angle
	var maximum := float(actor.data.profile.RangeLerpAngleSpeed) * rotation_wait
	if absf(desired) > 90.0:
		current += clampf(wrapf(desired - current, -180.0, 180.0), -maximum, maximum)
		actor.ranged_presentation.set_angle(current)
		if absf(current) > 90.0:
			actor.facing = 1.0 if direction.x >= 0.0 else -1.0
	else:
		actor.facing = 1.0 if direction.x >= 0.0 else -1.0
		desired = rad_to_deg(atan2(-direction.y, direction.x * actor.facing))
		current += clampf(wrapf(desired - current, -180.0, 180.0), -maximum, maximum)
		actor.ranged_presentation.set_angle(current)
	actor.ranged_presentation.set_aiming(true)


func _enter_attack() -> void:
	_change("attack")
	if attack_index == 0:
		actor.get_parent().audio.play_event("bow_shoot", actor)
	animation_angle = float(actor.ranged_presentation.angle)
	actor._sync_visuals()
	shot_origin = (
		actor.visuals[settings.anchor_go].global_transform * Assets.vec(settings.anchor_local)
	)
	var radians := deg_to_rad(animation_angle)
	var direction := Vector2(cos(radians) * actor.facing, -sin(radians))
	shot_angle = direction.angle()
	actor.ranged_presentation.set_aiming(false)
	if targeting_attack:
		flip_direction = 1.0 if target.position.x >= actor.position.x else -1.0
		if flip_direction != actor.facing:
			entry_phase = "flip_start"
			actor.play_combat_motion("FlipStart", actor.combat_animation_index)
			return
	targeting_attack = false
	_begin_attack_motion()


func _step_attack_entry() -> void:
	if not _finished():
		return
	elapsed = 0.0
	if entry_phase == "flip_start":
		# Direction is captured before FlipStart; movement during the two clips
		# cannot retarget it. Native arrow origin/angle were captured even earlier.
		actor.facing = flip_direction
		entry_phase = "flip_end"
		actor.play_combat_motion("FlipEnd", actor.combat_animation_index)
	else:
		entry_phase = ""
		targeting_attack = false
		_begin_attack_motion()


func _begin_attack_motion() -> void:
	elapsed = 0.0
	actor.play_combat_motion("Attack", attack_index, animation_angle)
	rounds = int(actor.data.profile.RangeAttackLimit)
	player_checked = false
	actor.apply_attack_movement(attack.AttackMovementInfo)
	# The original coroutine checks before its first yield. Frame-zero melee
	# and arrow attacks would be missed if the first check waited another tick.
	_check_attack_frame()


func _check_attack_frame() -> void:
	var frame := _frame()
	var check: Dictionary = attack.AttackCheckInfo
	if frame < int(check.AttackCheckStartFrame):
		return
	if attack_index == 0:
		if rounds > 0:
			rounds -= 1
			var arrow: Node2D = actor.get_parent().spawn_arrow(
				shot_origin,
				shot_angle,
				float(actor.data.profile.ProjectileSpeed),
				actor,
				int(check.RangeDamage)
			)
			arrow_launched.emit(arrow)
	elif frame < int(check.AttackCheckEndFrame):
		_melee(check)


func _melee(check: Dictionary) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(check.AttackRange.x, check.AttackRange.y) * actor.PIXELS_PER_UNIT
	var point: Vector2 = (
		center()
		+ (
			Vector2(float(check.AttackPoint.x) * actor.facing, -float(check.AttackPoint.y))
			* actor.PIXELS_PER_UNIT
		)
	)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = Collision.PLAYER | Collision.DAMAGEABLE
	for contact: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query):
		var body: Node = contact.collider
		if body == target:
			if not player_checked:
				player_checked = true
				var knockback: Dictionary = check.KnockBackMovementInfo.duplicate(true)
				if float(knockback.Duration) == 0.0:
					target.receive_damage(float(check.MeleeDamage))
				else:
					knockback.DirectionX = actor.facing
					target.receive_damage(float(check.MeleeDamage), knockback)
		elif (
			body.get_meta("source_layer", "") == "InteractiveWall"
			and body.has_method("receive_study_hit")
		):
			# The source adds the player to its exclusion set even for a wall hit.
			player_checked = true
			body.receive_study_hit({"Damage": wall_damage, "interaction": 4}, actor.facing)


func center() -> Vector2:
	return actor.global_position + actor.body_shape.position


func too_close() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = float(actor.data.profile.RangeCloseDistance) * actor.PIXELS_PER_UNIT
	query.shape = shape
	query.transform = Transform2D(0.0, center())
	query.collision_mask = Collision.PLAYER
	return actor.get_world_2d().direct_space_state.intersect_shape(query).any(
		func(contact: Dictionary): return contact.collider == target
	)


func cancel() -> void:
	if state == "cancel":
		return
	actor.ranged_presentation.set_aiming(false)
	_change("cancel")
	entry_phase = ""
	actor.play_combat_motion("AttackCancel", actor.combat_animation_index)


func reset() -> void:
	if settings.is_empty():
		return
	actor.ranged_presentation.set_aiming(false)
	entry_phase = ""
	rounds = 0
	_change("idle")
	if not actor.dead:
		actor.play_motion("Idle")


func _change(value: String) -> void:
	if state == "post" and value != state:
		attack_index = 0
	if state == "attack" and value != state:
		# AttackState.Exit resets Animator.Index, not the stored AttackIndex.
		actor.combat_animation_index = 0
	state = value
	elapsed = 0.0
	state_changed.emit(value)


func _finished() -> bool:
	return actor.motion_duration > 0.0 and elapsed > actor.motion_duration


func _frame() -> int:
	if actor.motion_animation.tracks.is_empty():
		return 0
	var clip: Dictionary = actor.motion_animation.tracks[0].clip
	var frame_count := float(clip.length) * float(clip.frame_rate)
	return floori(fmod(elapsed * float(clip.speed) * float(clip.frame_rate), frame_count))
