extends "res://Samples/ArtDirection/Runtime/OriginalRangedCombatBase.gd"
## Original bow decisions around its ranged/melee sequence and common navigation states.

const Positioning = preload("res://Samples/ArtDirection/Runtime/OriginalRangedPositioning.gd")

var sequence: RefCounted
var decision: Dictionary
var random := RandomNumberGenerator.new()
var can_run_away := true
var retreat_pending := false
var cancel_pending := false
var first_alarm := true


func configure(enemy: CharacterBody2D) -> void:
	actor = enemy
	if actor.data.kind != "EnemyBowMan":
		return
	var source: Dictionary = Assets.read_json(Assets.ROOT + "bow_combat.json")
	settings = source.common
	decision = (
		actor.data.bow_binding
		if actor.data.has("bow_binding")
		else source.actors[str(int(actor.data.go))]
	)
	sequence = actor.bow_attack
	sequence.state_changed.connect(_on_attack_state)
	attack = actor.data.profile.AttackInfoList[0]
	retreat.combat_ref = weakref(self)
	door_action.combat_ref = weakref(self)
	leash_point = _ground_point()
	random.randomize()


func step(delta: float) -> float:
	if settings.is_empty() or not is_instance_valid(target):
		return super.step(delta)
	if target.dead:
		return super.step(delta)
	if cancel_pending:
		cancel_pending = false
		door_action.reset()
		sequence.cancel()
		return 0.0
	if state == "alarm":
		elapsed += delta
		if _animation_finished():
			_change("idle")
			actor.play_motion("Idle")
		return 0.0
	# Native LateChangeState keeps the first request. Group Retarget runs
	# before the private close-range roll and therefore wins over RunAway.
	if retarget_pending:
		retarget_pending = false
		retreat_pending = false
		_enter_retreat("retarget")
		return 0.0
	if retreat_pending:
		retreat_pending = false
		_enter_retreat()
		return 0.0
	if sequence.active():
		sequence.step(delta)
		elapsed = sequence.elapsed
		return 0.0
	return super.step(delta)


func _enter_ready() -> void:
	_change("ready")
	Positioning.execute(actor.get_parent(), settings.positioning)
	if decision.can_alarm and _try_alarm():
		return
	# Source CheckClosePoint refuses a second close decision while AttackIndex
	# still holds melee after cancellation. Only Post exit clears that index.
	var close: bool = sequence.attack_index != 1 and _too_close()
	if close and can_run_away and random.randi_range(0, 99) < float(decision.run_away_weight):
		can_run_away = false
		retreat_pending = true
		return
	var index := 1 if close else 0
	attack = actor.data.profile.AttackInfoList[index]
	sequence.begin(target, index)


func _try_alarm() -> bool:
	var origin := _ground_point()
	var recipients: Array[Node] = []
	var request := false
	for enemy: Node in actor.get_parent().enemies:
		if enemy == actor or enemy.dead or not enemy.source_active():
			continue
		var point: Vector2 = enemy.ranged_combat._ground_point()
		if (
			absf(point.x - origin.x)
			>= float(actor.data.profile.AlarmDistance) * actor.PIXELS_PER_UNIT
		):
			continue
		var query := PhysicsRayQueryParameters2D.create(
			actor.body_shape.global_position,
			enemy.body_shape.global_position,
			Collision.SIGHT_SURFACE
		)
		if not actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		recipients.append(enemy)
		request = (
			request or (is_equal_approx(point.y, origin.y) and not enemy.ranged_combat.acquired)
		)
	if not request:
		return false
	# Reuse the current chase adapter for receivers. The source has a separate
	# AlarmAction path via the caller; that exact intermediate path is pending.
	for enemy: Node in recipients:
		enemy.ranged_combat.acquired = true
	actor.get_parent().audio.play_event("bow_alarm", actor)
	if first_alarm:
		first_alarm = false
		_change("alarm")
		actor.play_combat_motion("Alarm")
		return true
	return false


func _on_attack_state(value: String) -> void:
	if value == "ready":
		attack = sequence.attack
	# OnAttackPostExit also runs when a weak-point hit interrupts recovery.
	if state == "post" and value != "post":
		can_run_away = true
	_change("shot" if value == "attack" else value)


func weak_point_changed(player: CharacterBody2D) -> void:
	if settings.is_empty() or actor.dead:
		return
	if sequence.attack_index == 1 and state in ["ready", "confirm"]:
		sequence.targeting_attack = true
	if state == "cancel":
		return
	actor.ranged_presentation.set_aiming(false)
	# LateChangeState retains the first queued transition. The targeting flag
	# above is still set even when another transition already owns this update.
	if not retarget_pending and not retreat_pending:
		sequence.target = player
		cancel_pending = true


func request_retarget() -> void:
	if not cancel_pending and not retreat_pending:
		super.request_retarget()


func _enter_retreat(value := "retreat") -> void:
	sequence.reset()
	super._enter_retreat(value)


func _enter_leash_ready() -> void:
	sequence.reset()
	super._enter_leash_ready()


func reset() -> void:
	if settings.is_empty():
		return
	sequence.reset()
	retreat_pending = false
	cancel_pending = false
	super.reset()
