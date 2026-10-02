extends CharacterBody2D
## Source enemy health, collision bounds, hit flash and death presentation.
## Combat decisions, source attack sequences and patrol live in separate modules.

signal damaged(amount: float)
signal defeated

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")
const SceneAnimation = preload("res://Samples/ArtDirection/Runtime/OriginalSceneAnimation.gd")
const Patrol = preload("res://Samples/ArtDirection/Runtime/OriginalEnemyPatrol.gd")
const Kunai = preload("res://Samples/ArtDirection/Runtime/OriginalEnemyKunai.gd")
const RangedPresentation = preload("res://Samples/ArtDirection/Runtime/OriginalRangedPresentation.gd")
const RifleCombat = preload("res://Samples/ArtDirection/Runtime/OriginalRifleCombat.gd")
const BowAttack = preload("res://Samples/ArtDirection/Runtime/OriginalBowAttack.gd")
const BowCombat = preload("res://Samples/ArtDirection/Runtime/OriginalBowCombat.gd")
const BombCombat = preload("res://Samples/ArtDirection/Runtime/OriginalBombCombat.gd")
const WeakPointPresentation = preload(
	"res://Samples/ArtDirection/Runtime/OriginalWeakPointPresentation.gd"
)
const PIXELS_PER_UNIT := 16.0

var data: Dictionary
var health := 0.0
var dead := false
var stun_remaining := 0.0
var spawn_active := true
var is_targetable := true
var source_time_scale := 1.0
var visuals: Dictionary = {}
var base_transforms: Dictionary = {}
var animated_properties: Dictionary = {}
var facing := 1.0
var patrol := Patrol.new()
var kunai := Kunai.new()
var ranged_presentation := RangedPresentation.new()
var rifle_combat := RifleCombat.new()
var bow_attack := BowAttack.new()
var bow_combat := BowCombat.new()
var bomb_combat := BombCombat.new()
var weakpoint_presentation := WeakPointPresentation.new()
var ranged_combat: RefCounted:
	get:
		if data.get("kind") == "EnemyBombMan":
			return bomb_combat
		return bow_combat if data.get("kind") == "EnemyBowMan" else rifle_combat
var motion_animation := SceneAnimation.new()
var motion := ""
var combat_animation_index := 0
var motion_duration := 0.0
var scene_animation: Node
var death_animation := SceneAnimation.new()
var origin := Vector2.ZERO
var body_shape := CollisionShape2D.new()
var hit_timer := Timer.new()
var death_time := 0.0
var knockback: Dictionary = {}
var knockback_time := 0.0
var knockback_distance := 0.0
var knockback_direction := 1.0


func configure(
	source: Dictionary,
	scene_visuals: Dictionary,
	animation: Node,
	navigation: RefCounted,
	sorting := Callable()
) -> void:
	data = source
	_index_animated_properties()
	kunai.actor = self
	health = float(data.profile.f_maximumHealth)
	position = Assets.vec(data.position)
	origin = position
	facing = float(data.facing)
	scene_animation = animation
	collision_layer = Collision.DAMAGEABLE | Collision.ENEMY_TARGET
	collision_mask = Collision.SOLID | Collision.ONE_WAY
	safe_margin = Patrol.SKIN
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(data.bounds_size)
	body_shape.shape = rectangle
	body_shape.position = Assets.vec(data.bounds_offset)
	add_child(body_shape)
	add_child(death_animation)
	add_child(motion_animation)
	hit_timer.one_shot = true
	hit_timer.ignore_time_scale = true
	hit_timer.timeout.connect(_set_flash.bind(0.0))
	add_child(hit_timer)

	for go in data.visuals:
		if not scene_visuals.has(go):
			continue
		var visual: Node2D = scene_visuals[go]
		visuals[go] = visual
		base_transforms[go] = visual.global_transform
		visual.animation_pose_changed.connect(_sync_visuals)
		if visual.material is ShaderMaterial:
			# Layer lighting textures remain shared, but hit flash belongs to this
			# enemy instance rather than every enemy using the same source material.
			visual.material = visual.material.duplicate()
	patrol.configure(self, navigation)
	ranged_presentation.configure(self, sorting)
	rifle_combat.configure(self)
	bow_attack.configure(self)
	bow_combat.configure(self)
	bomb_combat.configure(self)
	weakpoint_presentation.configure(self)


func receive_study_hit(hit: Dictionary, direction: float) -> bool:
	if dead or not hit.has("Damage"):
		return false
	# InGameEntity.RequestDamage releases the targeting lock even at zero damage.
	is_targetable = true
	var amount := maxf(0.0, float(hit.Damage))
	var source_actor: Node = hit.get("source_actor")
	var strong_attack := not hit.has("kind") and int(hit.get("interaction", 4)) == 8
	if is_instance_valid(source_actor) and source_actor.has_signal("camera_shake_requested"):
		if not hit.has("kind"):
			var shake := "StrongAttack" if strong_attack else "Attack"
			# Stack-heavy feedback belongs to the source weak-point execution path.
			if shake == "Attack" or kunai.weak_points == 0:
				source_actor.camera_shake_requested.emit(shake)
	var before := health
	if not data.invincible:
		health = clampf(health - amount, 0.0, float(data.profile.f_maximumHealth))
	var feedback := "AttackHitEffect"
	if hit.get("kind") == "kunai_stuck":
		feedback = "ShurikenStuckEffect"
	elif hit.get("kind") == "kunai_dash":
		feedback = "ShurikenDashHitEffect"
	if hit.get("kind") == "weak_execution" or strong_attack:
		_consume_weak_point_feedback(source_actor)
	if hit.get("kind") == "weak_execution":
		# ShurikenDashAttack has no bright/time switch case in OnDamaged.
		hit_timer.stop()
		_set_flash(0.0)
	else:
		hit_timer.start(float(data.common[feedback + "Time"]))
		_set_flash(float(data.common[feedback + "Brightness"]))
	if not hit.has("kind") and (strong_attack or data.kind != "EnemyRifleMan"):
		get_parent().audio.play_event("enemy_hit", self)
	damaged.emit(before - health)

	if health <= 0.0:
		_die(hit.get("source_actor"))
		if (
			hit.get("kind") == "kunai_dash"
			and is_instance_valid(source_actor)
			and source_actor.has_signal("camera_shake_requested")
		):
			# The kill event replaces the generic teleport impulse generated earlier.
			source_actor.camera_shake_requested.emit("ShurikenDashDie")
	elif data.knockback and not data.invincible and hit.has("AttackKnockBackInfo"):
		knockback = hit.AttackKnockBackInfo
		knockback_time = 0.0
		knockback_distance = 0.0
		knockback_direction = direction
	return true


func _consume_weak_point_feedback(source_actor: Node) -> void:
	var stacks := kunai.weak_points
	if stacks <= 0:
		return
	if is_instance_valid(source_actor) and source_actor.has_signal("camera_shake_requested"):
		source_actor.camera_shake_requested.emit("ShurikenStack%d" % stacks)
	# OnDamaged reads the victim's current stacks before ResetWeakPoint. This
	# also applies to zero-damage secondary hits and ordinary strong attacks.
	get_parent().audio.play_event("enemy_stack_hit_%d" % stacks, self)
	kunai.weak_points = 0
	kunai.reset_time = 0.0
	weakpoint_presentation.reset()


func _physics_process(delta: float) -> void:
	if dead:
		_update_corpse(delta)
		return

	var stunned := stun_remaining > 0.0
	if stunned:
		# HitState stops decisions and animation. The shared movement path below
		# still applies gravity and incoming attack knockback, as in LateUpdate.
		kunai.update(delta)
		stun_remaining = maxf(0.0, stun_remaining - delta * source_time_scale)
		velocity.x = 0.0
		if stun_remaining <= 0.0:
			on_source_time_scale(source_time_scale)
			motion = ""
			ranged_combat.reset()
			var target: Node = ranged_combat.target
			if int(data.character_type) != 0 and is_instance_valid(target) and not target.dead:
				if (
					position.distance_to(target.position)
					<= float(data.profile.LeashRange) * PIXELS_PER_UNIT
				):
					ranged_combat.acquired = true
					ranged_combat._enter_route("chase", target.position)

	elif source_time_scale == 0.0:
		# StateMachine's elapsed clock and weak-point Update use global delta,
		# while its custom coroutine and Animator are paused by TimeManager.
		ranged_combat.elapsed += delta
		if data.kind == "EnemyBombMan":
			bomb_combat.clock += delta
		elif data.kind == "EnemyBowMan" and bow_attack.active():
			bow_attack.elapsed += delta
		kunai.update(delta)
		if knockback.is_empty():
			velocity = Vector2.ZERO
			return
	else:
		velocity.x = ranged_combat.step(delta)
	if dead:
		return  # Self-destruction deactivates the source object during its attack update.
	if source_time_scale != 0.0 and not stunned:
		kunai.update(delta)
	var curve_movement := not knockback.is_empty()
	if not knockback.is_empty() and float(knockback.Duration) > 0.0:
		knockback_time = minf(knockback_time + delta, float(knockback.Duration))
		var progress := knockback_time / float(knockback.Duration)
		var distance := (
			SourceCurve.evaluate(knockback.Curve, progress)
			* float(knockback.Power)
			* PIXELS_PER_UNIT
		)
		velocity.x = (distance - knockback_distance) * knockback_direction / delta
		knockback_distance = distance
		if progress >= 1.0:
			knockback = {}
	velocity.y += float(data.gravity) * PIXELS_PER_UNIT * delta
	if not curve_movement:
		velocity *= source_time_scale
	move_and_slide()
	if not curve_movement:
		# EnemyStateMachine multiplies the returned displacement by Scale again;
		# unlike PlayerCollision2D, its cached velocity therefore contains Scale².
		velocity *= source_time_scale
	_sync_visuals()


func on_source_time_scale(value: float) -> void:
	source_time_scale = value
	for visual: Node in visuals.values():
		visual.set_meta("source_animation_scale", 0.0 if stun_remaining > 0.0 else value)


func stun(duration: float) -> bool:
	if dead or not spawn_active or stun_remaining > 0.0:
		return false  # Native AddHitTime prevents refreshing an existing freeze.
	var frozen_tracks := motion_animation.tracks.duplicate(true)
	var frozen_scene_tracks: Array = (
		scene_animation
		. tracks
		. filter(func(track): return track.clip.go in data.visuals)
		. duplicate(true)
	)
	var frozen_motion := motion
	ranged_combat.reset()
	# State exit cancels pending shots, while HitState keeps the current pose.
	scene_animation.release_visuals(data.visuals)
	motion_animation.tracks = frozen_tracks
	motion_animation.tracks.append_array(frozen_scene_tracks)
	motion = frozen_motion
	knockback = {}
	velocity = Vector2.ZERO
	stun_remaining = duration
	if int(data.character_type) == 1:
		data.character_type = 2
	ranged_combat._change("hit")
	get_parent().audio.stop_events(self)
	on_source_time_scale(source_time_scale)
	return true


func apply_attack_movement(movement: Dictionary) -> void:
	# Source CurveMovement replaces the previous movement slot even at zero
	# duration. Such bow attacks must not leave a permanent active knockback.
	# Incoming hit dictionaries may belong to a shared profile; replace the slot
	# instead of clearing that dictionary in place.
	knockback = {}
	if float(movement.Time) <= 0.0:
		return
	knockback = {"Curve": movement.Curve, "Power": movement.Distance, "Duration": movement.Time}
	knockback_time = 0.0
	knockback_distance = 0.0
	knockback_direction = facing


func source_active() -> bool:
	# GameManager includes a corpse until its original GameObject deactivates.
	if not is_inside_tree() or not spawn_active:
		return false
	if not dead:
		return true
	return (
		not data.death_tracks.is_empty()
		and death_time < float(data.profile.DisappearDelayTime) + float(data.corpse_fade_time)
	)


func set_spawn_active(value: bool) -> void:
	spawn_active = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	collision_layer = (Collision.DAMAGEABLE | Collision.ENEMY_TARGET) if value else 0
	is_targetable = value
	if not value:
		scene_animation.release_visuals(data.visuals)
	for visual: Node2D in visuals.values():
		visual.visible = value and visual.data.get("visible", true)
	if value:
		play_motion("Idle")
		_sync_visuals()


func force_repeat_idle() -> void:
	# RepeatingMonsterSpawner calls ChangeState(Idle) on every alpha frame;
	# retain gravity/collisions and reset attack/fuse state rather than freezing
	# this body's entire processing or marking it Peaceful indefinitely.
	if not dead:
		ranged_combat.reset()
		play_motion("Idle")


func apply_repeat_tint(color: Color) -> void:
	# BombMan's source coroutine changes GFX.color only. Health bars, weak-point
	# graphics and sibling renderers must not inherit the replacement's fade.
	if visuals.has(data.primary_visual):
		visuals[data.primary_visual].modulate = color


func play_motion(trigger: String) -> void:
	if motion == trigger or not data.motion_tracks.has(trigger):
		return
	motion = trigger
	_reset_animation_properties(data.motion_tracks[trigger])
	scene_animation.release_visuals(data.visuals)
	motion_animation.tracks.clear()
	motion_animation.configure(data.motion_tracks[trigger], visuals)
	_sync_visuals()


func receive_study_kunai(player: Node) -> bool:
	return kunai.attach(player)


func play_combat_motion(trigger: String, index := 0, angle := 0.0) -> void:
	combat_animation_index = index
	var tracks := ranged_presentation.animation(trigger, index, angle)
	if tracks.is_empty():
		return
	motion = "%s:%d" % [trigger, index]
	_reset_animation_properties(tracks)
	# Animator state timing still exists when a clip binding has no renderer in
	# this prefab (the rifle's inherited RunReady clip is one such case).
	motion_duration = 0.0
	for clip: Dictionary in tracks:
		var speed := absf(float(clip.speed))
		motion_duration = maxf(motion_duration, float(clip.length) / speed if speed > 0.0 else INF)
	scene_animation.release_visuals(data.visuals)
	motion_animation.tracks.clear()
	motion_animation.configure(tracks, visuals)
	_sync_visuals()


func _reset_animation_properties(tracks: Array) -> void:
	# Unity Write Defaults restores properties absent from the next state.
	# Reset before applying its first frame so no intermediate pose is drawn.
	if not tracks.any(func(track: Dictionary): return track.get("write_defaults", false)):
		return
	for go in animated_properties:
		if visuals.has(go):
			visuals[go].reset_animation_properties(animated_properties[go])


func _index_animated_properties() -> void:
	# Write Defaults affects properties bound anywhere in this Animator, not
	# unrelated sprites controlled exclusively by RotationPart or gameplay.
	var groups: Array = data.motion_tracks.values()
	for state: Dictionary in data.get("combat_animations", {}).values():
		groups.append(state.get("tracks", []))
		for variant: Dictionary in state.get("variants", []):
			groups.append(variant.tracks)
	for tracks: Array in groups:
		for track: Dictionary in tracks:
			if not animated_properties.has(track.go):
				animated_properties[track.go] = []
			if track.kind not in animated_properties[track.go]:
				animated_properties[track.go].append(track.kind)


func _sync_visuals() -> void:
	var mirrored := facing != float(data.facing)
	var pivot := Assets.vec(data.gfx_position)
	for go in visuals:
		var pose: Transform2D = base_transforms[go]
		pose.origin += visuals[go].animation_offset
		pose = weakpoint_presentation.pose_for(go, pose)
		if mirrored and go in data.gfx_visuals:
			# Mirror the source GFX subtree about its pivot. Health bars and other
			# sibling renderers move with the body without being flipped.
			pose.x.x *= -1.0
			pose.y.x *= -1.0
			pose.origin.x = 2.0 * pivot.x - pose.origin.x
		pose.origin += position - origin
		visuals[go].global_transform = pose
	ranged_presentation.apply()
	weakpoint_presentation.apply_visibility()


func player_contact_info() -> Dictionary:
	# Retarget shares the RunAway coroutine, but has a different native state;
	# only the actual retreat state suppresses PlayerCollision2D's separation.
	return {"center": body_shape.global_position, "run_away": ranged_combat.state == "retreat"}


func _set_flash(amount: float) -> void:
	for go in data.get("hit_visuals", visuals.keys()):
		if not visuals.has(go):
			continue
		var visual: Node2D = visuals[go]
		if visual.material is ShaderMaterial:
			visual.material.set_shader_parameter("hit_blend", amount)


func _die(source_actor: Node) -> void:
	# The shipped pool ignores Borrow's stoppable argument. All three enemy
	# subclasses return old events before base.OnDead starts the player's renewal cue.
	get_parent().audio.stop_events(self)
	if data.kind == "EnemyBowMan":
		var audio: Node = get_parent().audio
		# The death event belongs to the stage, so hiding the source bow does not
		# truncate its voice. Native OnDead returns older sounds before this call.
		audio.play_event("bow_death", self)
	if is_instance_valid(source_actor) and source_actor is Player:
		source_actor.wind_buff.on_player_kill()
		# Native OnDead plays this for every player kill, including when no buff is active.
		get_parent().audio.play_event("wind_buff_renewal", self)
	if data.kind != "EnemyRifleMan":
		if source_actor != self:
			get_parent().audio.play_event("enemy_common_death", self)
	rifle_combat.reset()
	bow_combat.reset()
	bomb_combat.reset()
	ranged_presentation.set_aiming(false)
	stun_remaining = 0.0
	on_source_time_scale(source_time_scale)
	dead = true
	kunai.weak_points = 0
	kunai.reset_time = 0.0
	weakpoint_presentation.reset()
	velocity = Vector2.ZERO
	_set_flash(0.0)
	set_deferred("collision_layer", 0)
	scene_animation.release_visuals(data.visuals)
	motion_animation.tracks.clear()
	if is_instance_valid(source_actor) and source_actor.has_method("restore_stamina"):
		source_actor.restore_stamina(float(data.profile.RefundStamina))

	if data.death_tracks.is_empty():
		# Bow and bomb enemies deactivate immediately in the shipped OnDead.
		for visual: Node2D in visuals.values():
			visual.hide()
	else:
		death_animation.configure(data.death_tracks, visuals)
	defeated.emit()


func _update_corpse(delta: float) -> void:
	if data.death_tracks.is_empty():
		return
	death_time += delta
	var elapsed := death_time - float(data.profile.DisappearDelayTime)
	if elapsed <= 0.0:
		return
	var alpha := 1.0 - clampf(elapsed / float(data.corpse_fade_time), 0.0, 1.0)
	if visuals.has(data.primary_visual):
		visuals[data.primary_visual].modulate.a = alpha
	if alpha <= 0.0:
		for visual: Node2D in visuals.values():
			visual.hide()
