extends "res://Samples/ArtDirection/Runtime/OriginalRangedCombatBase.gd"
## Rifle-specific reload, confirmation, ray shot and post-attack behavior.

signal shot_fired(origin: Vector2, direction: Vector2, hit: Dictionary)

const Cues = preload("res://Samples/ArtDirection/Runtime/OriginalRifleCues.gd")
const Positioning = preload("res://Samples/ArtDirection/Runtime/OriginalRangedPositioning.gd")

var cues: Node
var ready_delay := 0.0
var tracking_wait := 0.0
var reloaded := false
var rounds := 0
var shot_direction := Vector2.RIGHT


func configure(enemy: CharacterBody2D) -> void:
	actor = enemy
	if actor.data.kind != "EnemyRifleMan":
		return
	settings = Assets.read_json(Assets.ROOT + "rifle_combat.json")
	retreat.combat_ref = weakref(self)
	door_action.combat_ref = weakref(self)
	door_action.kick_sound = "rifle_kick"
	attack = actor.data.profile.AttackInfoList[0]
	# EnemyStateMachine.Start stores the ground cell, not the sprite pivot.
	leash_point = _ground_point()
	cues = Cues.new()
	actor.add_child(cues)
	cues.configure(actor, settings)


func step(delta: float) -> float:
	if settings.is_empty() or not is_instance_valid(target):
		return super.step(delta)
	if target.dead or not door_action.phase.is_empty() or retarget_pending:
		return super.step(delta)
	if state not in ["ready", "confirm", "shot", "post"]:
		return super.step(delta)
	elapsed += delta
	match state:
		"ready":
			if _too_close():
				_enter_retreat()
			elif _animation_finished():
				ready_delay -= delta
				if ready_delay <= 0.0:
					reloaded = true
					_enter_confirm()
		"confirm":
			if _too_close():
				_enter_retreat()
			else:
				var duration := float(attack.AttackCheckInfo.AttackConfirmTime)
				cues.advance_blink(delta, duration)
				if elapsed < duration * float(settings.tracking_fraction):
					_track(delta)
				if elapsed >= duration:
					_enter_shot()
		"shot":
			if (
				rounds > 0
				and _animation_frame() >= int(attack.AttackCheckInfo.AttackCheckStartFrame)
			):
				rounds -= 1
				_fire()
			if _animation_finished():
				_change("post")
				actor.play_combat_motion("AttackPost")
		"post":
			actor.ranged_presentation.set_aiming(false)
			if _animation_finished():
				_change("idle")
				actor.play_motion("Idle")
	return 0.0


func reset() -> void:
	if settings.is_empty():
		return
	cues.stop()
	door_action.reset()
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	acquired = false
	reloaded = false
	tracking_wait = 0.0
	chase_preparing = false
	retarget_pending = false
	route.clear()
	_change("idle")
	if not actor.dead:
		actor.play_motion("Idle")


func _enter_ready() -> void:
	actor.facing = 1.0 if target.position.x >= actor.position.x else -1.0
	_change("ready")
	Positioning.execute(actor.get_parent(), settings.positioning)
	if reloaded:
		# Native LateChangeState keeps the first queued transition. A group
		# retarget request therefore wins over the already-loaded shortcut.
		if not retarget_pending:
			_enter_confirm()
		return
	ready_delay = float(attack.AttackCheckInfo.AttackReadyTime)
	actor.ranged_presentation.set_aiming(false)
	actor.play_combat_motion("AttackReady")
	actor.get_parent().audio.play("rifle_reload")


func _enter_confirm() -> void:
	_change("confirm")
	# The source has no AttackConfirm Animator transition: freeze the finished
	# reload state while the independent RotationPart handles gun targeting.
	actor.motion_animation.set_process(false)
	cues.begin_aim()


func _track(delta: float) -> void:
	if tracking_wait > 0.0:
		tracking_wait -= delta
		return
	tracking_wait = float(actor.data.profile.RangeRotationFrame) * delta
	var offset := _target_center() - _center()
	actor.facing = 1.0 if offset.x >= 0.0 else -1.0
	var desired := rad_to_deg(atan2(-offset.y, offset.x * actor.facing))
	var current: float = actor.ranged_presentation.angle
	var difference := wrapf(desired - current, -180.0, 180.0)
	var maximum := float(actor.data.profile.RangeLerpAngleSpeed) * tracking_wait
	var angle := current + clampf(difference, -maximum, maximum)
	actor.ranged_presentation.set_aiming(true)
	actor.ranged_presentation.set_angle(angle)
	cues.sync()
	var muzzle: Vector2 = cues.lines.aim.global_position
	var direction: Vector2 = cues.lines.aim.global_transform.x.normalized()
	var distance: float = float(settings.aim_distance) * actor.PIXELS_PER_UNIT
	var hit := _ray(muzzle, muzzle + direction * distance, Collision.SIGHT_SURFACE)
	if not hit.is_empty():
		distance = muzzle.distance_to(hit.position)
	cues.set_aim_distance(distance)


func _enter_shot() -> void:
	_change("shot")
	cues.lines.aim.hide()
	actor.motion_animation.set_process(true)
	var angle := float(actor.ranged_presentation.angle)
	shot_direction = Vector2(cos(deg_to_rad(angle)) * actor.facing, -sin(deg_to_rad(angle)))
	actor.play_combat_motion("Attack", 0, angle)
	actor.get_parent().audio.play("rifle_shot")
	actor.get_parent().spawn_effect(
		"Eff_RifleMan_Shot",
		actor.global_position,
		-deg_to_rad(angle * actor.facing),
		actor.facing < 0.0,
		actor
	)
	reloaded = false
	rounds = int(actor.data.profile.RangeAttackLimit)
	# Source attack movement replaces the same slot used by incoming knockback.
	actor.apply_attack_movement(attack.AttackMovementInfo)


func _fire() -> void:
	var distance: float = float(settings.shot_distance) * actor.PIXELS_PER_UNIT
	var origin := _center()
	var hit := _ray(
		origin, origin + shot_direction * distance, Collision.RAY_SURFACE | Collision.PLAYER
	)
	if not hit.is_empty() and hit.collider.has_method("receive_damage"):
		hit.collider.receive_damage(float(settings.damage))
	var offset: Dictionary = attack.AttackCheckInfo.AttackPoint
	var trace_origin: Vector2 = (
		origin + Vector2(float(offset.x) * actor.facing, -float(offset.y)) * actor.PIXELS_PER_UNIT
	)
	var wall := _ray(
		trace_origin, trace_origin + shot_direction * distance, Collision.SIGHT_SURFACE
	)
	cues.fire(trace_origin.distance_to(wall.position) if not wall.is_empty() else distance)
	if not wall.is_empty():
		actor.get_parent().spawn_effect(
			"Eff_Enemy_Bullet_Ground", wall.position, shot_direction.angle() - PI
		)
	shot_fired.emit(origin, shot_direction, hit)


func _enter_retreat(value := "retreat") -> void:
	if state == "ready" and _animation_finished():
		reloaded = true
	cues.lines.aim.hide()
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	# Geometry clamps before separation in the original. Do not clamp again:
	# the final search can move the occupied candidate beyond the leash boundary.
	_enter_route(value, retreat.destination(), false)


func _enter_leash_ready() -> void:
	acquired = false
	cues.stop()
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	_change("leash_ready")
	actor.play_combat_motion("RunReady")
