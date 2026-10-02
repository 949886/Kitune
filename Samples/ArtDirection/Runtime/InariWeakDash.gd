extends RefCounted
## PlayerDashAttackState: snapshot stacks, approach, frame-stop, hit and recovery.

signal phase_changed(value: String)
signal hit_delivered(target: Node, amount: float)

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")

var actor: CharacterBody2D
var stage: Node
var target: Node
var phase := ""
var attack: Dictionary
var landing: Dictionary
var stacks := 0
var angle := 0.0
var direction := Vector2.RIGHT
var motion_start := Vector2.ZERO
var motion_end := Vector2.ZERO
var motion_curve: Dictionary
var motion_time := 0.0
var motion_duration := 0.0
var phase_time := 0.0


func configure(player: CharacterBody2D, source_stage: Node) -> void:
	actor = player
	stage = source_stage


func active() -> bool:
	return not phase.is_empty()


func start(enemy: Node) -> bool:
	if active() or not is_instance_valid(enemy) or enemy.dead or enemy.kunai.weak_points <= 0:
		return false
	actor.air_attack.leave()
	target = enemy
	target.is_targetable = false
	stacks = target.kunai.weak_points
	attack = actor.combat.WeakPointAttackInfo
	landing = target.kunai.weak_attack_path(actor)
	direction = (landing.recovery - _center()).normalized()
	angle = direction.angle()
	actor.facing = 1.0 if direction.x >= 0.0 else -1.0
	actor.climbing = false
	actor.ceiling_hang = false
	actor.wall_jump_time = 0.0
	actor.path_time = actor.path_duration
	actor.attack_info.clear()
	actor.throw_buffer_until = 0.0
	actor.action_state = "weakpoint_execution"
	actor.collision_mask = Collision.SOLID
	actor.sprite.facing = actor.facing
	actor.sprite.gfx_rotation = angle + (PI if actor.facing < 0.0 else 0.0)
	actor.sprite.play("weak_dash_ready", true)
	_begin_motion(landing.approach, actor.physics.dashPhysicsCurve, attack.AttackMovementInfo.Time)
	_change("ready")
	_effect("Eff_Player_DashAttack", _center(), true)
	return true


func step(delta: float, horizontal: float) -> void:
	if not active() or stage.combat_clock.scale_value == 0.0:
		return
	phase_time += delta * actor.source_time_scale
	if phase == "impact_wait":
		# MyWaitForUpdate was first polled when frame-stop began. Its next poll
		# resumes the custom coroutine only after TimeManager permits it to run.
		_attack()
		stage.chromatic.trigger(clampi(stacks - 1, 0, 3), delta)
		_begin_motion(
			landing.recovery, attack.AttackMovementInfo.Curve, attack.AttackMovementInfo.PostTime
		)
		actor.sprite.play("weak_dash_idle" if landing.grounded else "weak_dash_fall", true)
		_change("post")
	_move(delta * actor.source_time_scale, horizontal)
	var clip: Dictionary = actor.sprite.clips[actor.sprite.clip_name]
	var animation_duration: float = float(clip.length) / float(clip.speed)
	if phase == "ready" and phase_time > animation_duration:
		_effect("Eff_Player_Attack_3", _center(), false)
		stage.combat_clock.stop_frames(
			int(attack.FrameStop[clampi(stacks - 1, 0, 3)]), actor.tuning.fixed_timestep
		)
		_change("impact_wait")
	elif phase == "post" and motion_time >= motion_duration and phase_time > animation_duration:
		finish()


func _begin_motion(end: Vector2, curve: Dictionary, duration: float) -> void:
	actor.wall_hold_time = float(actor.physics.WallHoldingTime)
	motion_start = _center()
	motion_end = end
	motion_curve = curve
	motion_duration = duration
	motion_time = 0.0
	actor.velocity = Vector2.ZERO


func _move(delta: float, horizontal: float) -> void:
	if motion_time >= motion_duration:
		actor.velocity = Vector2.ZERO
		return
	motion_time = minf(motion_duration, motion_time + delta)
	var desired := motion_start.lerp(
		motion_end, SourceCurve.evaluate(motion_curve, motion_time / motion_duration)
	)
	var movement := desired - _center()
	# The native curve driver permits held-direction continuation on either axis
	# of approach; compare against movement direction rather than the GFX facing.
	var continuation: float = float(actor.physics.moveSpeed) * actor.units * delta
	if horizontal != 0.0 and signf(movement.x) == horizontal and absf(movement.x) < continuation:
		movement.x = horizontal * continuation
		motion_end.x += movement.x
	actor.velocity = movement / delta
	actor.move_source_velocity()


func _attack() -> void:
	if not is_instance_valid(target) or target.dead:
		return
	var side := 1.0 if target.global_position.x >= _center().x else -1.0
	var packet := {
		"Damage": attack.Damages[stacks],
		"kind": "weak_execution",
		"interaction": 16,
		"source_actor": actor,
		"weak_point_index": stacks,
		"angle": angle,
		"AttackKnockBackInfo": attack.KnockbackInfos[stacks].duplicate(true)
	}
	if stacks == 3:
		_effect("Eff_PlayerThirdStack", target.global_position, true)
	_effect("Eff_WeaknessExposure_ver%d" % stacks, target.global_position, false)
	target.receive_study_hit(packet, side)
	hit_delivered.emit(target, float(packet.Damage))
	actor.attacked.emit(packet)
	# Native code rereads the PRIMARY target's stacks after RequestDamage. Its
	# reset normally makes secondary damage zero; do not substitute each victim.
	packet.Damage = attack.Damages[target.kunai.weak_points]
	packet.weak_point_index = target.kunai.weak_points
	var check: Dictionary = attack.AttackCheckInfo
	var box := RectangleShape2D.new()
	box.size = Vector2(check.AttackRange.x, check.AttackRange.y) * actor.units
	var offset: Vector2 = (
		Vector2(check.AttackOffset.x * side, -check.AttackOffset.y * side) * actor.units
	)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.transform = Transform2D(0.0, _center() + offset)
	query.collision_mask = (
		Collision.ENEMY_TARGET | Collision.INTERACTIVE_WALL | Collision.DEFAULT_ENTITY
	)
	query.collide_with_areas = true
	var capacity: int = actor.targeting.settings.query_capacity
	var contacts: Array = []
	while true:
		contacts = actor.get_world_2d().direct_space_state.intersect_shape(query, capacity)
		if contacts.size() < capacity:
			break
		capacity *= 2
	for collision: Dictionary in contacts:
		if collision.collider != target and collision.collider.has_method("receive_study_hit"):
			collision.collider.receive_study_hit(packet, side)
	var haptic: Dictionary = attack.GamePadHapticInfo
	if actor.targeting.gamepad_device >= 0:
		Input.start_joy_vibration(
			actor.targeting.gamepad_device,
			haptic.LowFrequency,
			haptic.HighFrequency,
			haptic.Duration
		)


func finish() -> void:
	actor.action_state = ""
	actor.sprite.gfx_rotation = 0.0
	actor.sprite.play("idle" if landing.grounded else "fall", true)
	actor.velocity = Vector2.ZERO
	actor.collision_mask = Collision.SOLID | Collision.ONE_WAY
	if is_instance_valid(actor.targeting.presentation):
		actor.targeting.presentation.set_active(false, true)
	_change("")
	target = null


func cancel() -> void:
	if not active():
		return
	if is_instance_valid(target):
		target.is_targetable = true
	stage.combat_clock.reset()
	finish()


func _center() -> Vector2:
	return actor.global_position + actor.body_shape.position


func _effect(key: String, point: Vector2, scaled: bool) -> void:
	stage.spawn_effect(key, point, angle, false, null, scaled)


func _change(value: String) -> void:
	phase = value
	phase_time = 0.0
	phase_changed.emit(value)
