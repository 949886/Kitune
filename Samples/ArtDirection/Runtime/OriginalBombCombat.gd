extends "res://Samples/ArtDirection/Runtime/OriginalRangedCombatBase.gd"
## EnemyBombMan's moving fuse and separate ready/confirm self-destruction path.

signal exploded(effect: Node)

const AnimationSound = preload("res://Samples/ArtDirection/Runtime/OriginalAnimationSound.gd")

var chase_sound := AnimationSound.new()

var clock := 0.0
var deadline := 0.0
var fuse_active := false
var targeted := false
var confirm_pending := false
var explosion_pending := false
var waiting := 0.0
var movement_speed := 1.0


func configure(enemy: CharacterBody2D) -> void:
	actor = enemy
	if actor.data.kind != "EnemyBombMan":
		return
	settings = Assets.read_json(Assets.ROOT + "bomb_combat.json")
	attack = actor.data.profile.AttackInfoList[0]
	leash_point = _ground_point()
	retargetable = false  # BombMan does not inherit the ranged positioning rule.
	door_action.combat_ref = weakref(self)
	door_action.attack_started.connect(_on_door_attack)


func step(delta: float) -> float:
	clock += delta
	if settings.is_empty() or not is_instance_valid(target) or target.dead:
		return super.step(delta)
	if actor.dead:
		return 0.0
	if explosion_pending:
		explode()
		return 0.0
	if confirm_pending:
		confirm_pending = false
		_enter_confirm()
		return 0.0
	if not door_action.phase.is_empty():
		door_action.step(delta)
		return 0.0
	match state:
		"ready", "confirm":
			elapsed += delta
			if _animation_finished():
				waiting -= delta * movement_speed
				if waiting <= 0.0:
					if state == "ready":
						confirm_pending = true
					else:
						explosion_pending = true
			return 0.0
		"confirm_entry":
			# OnAttackConfirmEnter yields one update before the base pattern
			# starts its animation and its additional confirmation wait.
			_change("confirm")
			actor.play_combat_motion("AttackConfirm")
			waiting = float(attack.AttackCheckInfo.AttackConfirmTime)
			return 0.0
		"chase":
			if chase_preparing:
				chase_preparation_time += delta
				if chase_preparation_time <= actor.motion_duration:
					return 0.0
				chase_preparing = false
				actor.play_combat_motion("Chase")
			if _inside_leash(_ground_point().x):
				if _in_attack_range() and _clear_sight():
					_play_chase_sound()
					if not fuse_active:
						_start_fuse()
					if clock >= deadline or targeted:
						confirm_pending = true
					else:
						# This is an absolute Time.time deadline which the source
						# additionally subtracts from; it is not a plain timer.
						deadline -= delta * movement_speed
				else:
					_cancel_fuse()
			return _walk_route(float(actor.data.profile.f_ChaseSpeed))
	return super.step(delta)


func _enter_ready() -> void:
	_change("ready")
	actor.facing = 1.0 if target.position.x >= actor.position.x else -1.0
	actor.play_combat_motion("AttackReady")
	waiting = float(attack.AttackCheckInfo.AttackReadyTime)


func _enter_route(value: String, destination: Vector2, clamp_leash := true) -> void:
	super._enter_route(value, destination, clamp_leash)
	if value == "chase":
		actor.get_parent().audio.play_event("bomb_patrol_voice", actor)


func _on_route_move() -> void:
	if state == "chase":
		_play_chase_sound()


func _play_chase_sound() -> void:
	chase_sound.step(actor, settings.chase_sound_frames, "bomb_chase")


func _start_fuse() -> void:
	fuse_active = true
	var duration := float(attack.AttackCheckInfo.AttackConfirmTime) / movement_speed
	if targeted:
		duration *= float(settings.targeted_time_scale)
	deadline = clock + duration * float(actor.data.profile.AttackConfirmTimeScale)
	# WaitForAttackConfirmTime has no visual interpolation and keeps its
	# coroutine handle after finishing; leaving range is what clears it.
	var visual: Node = actor.visuals[actor.data.primary_visual]
	visual.material.set_shader_parameter("hit_glow", float(settings.ready_glow))
	var audio: Node = actor.get_parent().audio
	audio.play_event("bomb_ready", actor)
	audio.play_event("bomb_ready_leg", actor)


func _cancel_fuse() -> void:
	if fuse_active:
		fuse_active = false
		actor._set_flash(0.0)


func _enter_confirm() -> void:
	door_action.reset()
	if not fuse_active:
		_start_fuse()
	actor.facing = 1.0 if _target_center().x >= _center().x else -1.0
	_change("confirm_entry")


func weak_point_changed(player: CharacterBody2D) -> void:
	if settings.is_empty() or actor.dead or int(actor.data.character_type) == 0:
		return
	target = player
	targeted = true
	# LateChangeState ignores a request for the current state, including
	# its entry coroutine; another weak point cannot restart confirmation.
	if state not in ["confirm_entry", "confirm"] and not explosion_pending:
		confirm_pending = true


func _chase_distance() -> float:
	return float(settings.chase_path_distance) * actor.PIXELS_PER_UNIT


func _on_door_attack() -> void:
	# Only the Chase helper subscribes to EnemyBombMan.OnAttackEnter.
	if state == "chase":
		explode()


func explode() -> void:
	if actor.dead:
		return
	explosion_pending = false
	var effect: Node = actor.get_parent().spawn_effect(settings.effect, actor.position, 0.0)
	var shape := RectangleShape2D.new()
	var bounds: Dictionary = attack.AttackCheckInfo.AttackRange
	shape.size = Vector2(bounds.x, bounds.y) * actor.PIXELS_PER_UNIT
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = _center()
	query.collision_mask = Collision.PLAYER | Collision.INTERACTIVE_WALL
	# Native OverlapBoxNonAlloc limits colliders, not unique entities. Walls
	# do not occlude this overlap, and ordinary enemies are outside its mask.
	for hit: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(
		query, int(settings.hit_limit)
	):
		var body: Node = hit.collider
		if body.collision_layer & Collision.PLAYER:
			body.receive_damage(float(settings.player_damage))
		elif "door" in body and is_instance_valid(body.door):
			body.door.receive_enemy_damage(float(settings.wall_damage), actor.facing)
	actor.receive_study_hit(
		{"Damage": actor.data.profile.f_maximumHealth, "source_actor": actor}, 0.0
	)
	# Native OnDead returns this actor's older sounds before OnAttackEnter
	# starts Explosion; hiding the actor must not cut off the final event.
	actor.get_parent().audio.play_event("bomb_explosion", actor)
	exploded.emit(effect)


func reset() -> void:
	if settings.is_empty():
		return
	confirm_pending = false
	explosion_pending = false
	_cancel_fuse()
	super.reset()
