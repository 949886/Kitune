extends CharacterBody2D
## Isolated INARI v0.2.1 controller port. Scene positions use pixels and a foot origin;
## source tuning uses Unity units and a collider-center origin. Convert only here.

signal attacked(hit: Dictionary)
signal teleported(from: Vector2, to: Vector2)
signal camera_shake_requested(kind: String)
signal health_changed(current: int, maximum: int)
signal respawned

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Curves = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")
const Controls = preload("res://Samples/ArtDirection/Runtime/InariInput.gd")
const Animator = preload("res://Samples/ArtDirection/Runtime/InariAnimation.gd")
const Audio = preload("res://Samples/ArtDirection/Runtime/OriginalAudio.gd")
const Damage = preload("res://Samples/ArtDirection/Runtime/InariDamage.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Targeting = preload("res://Samples/ArtDirection/Runtime/InariWeakPointTargeting.gd")
const WeakDash = preload("res://Samples/ArtDirection/Runtime/InariWeakDash.gd")
const AimTime = preload("res://Samples/ArtDirection/Runtime/InariAimTime.gd")
const MovementInput = preload("res://Samples/ArtDirection/Runtime/InariMovementInput.gd")
const KunaiVisual = preload("res://Samples/ArtDirection/Runtime/InariKunaiVisual.gd")
const KunaiFade = preload("res://Samples/ArtDirection/Runtime/InariKunaiFade.gd")
const KunaiEffects = preload("res://Samples/ArtDirection/Runtime/InariKunaiEffects.gd")
const StaminaFeedback = preload("res://Samples/ArtDirection/Runtime/InariStaminaFeedback.gd")
const WindBuff = preload("res://Samples/ArtDirection/Runtime/InariWindBuff.gd")
const WindTrail = preload("res://Samples/ArtDirection/Runtime/InariWindTrail.gd")
const GroundSnap = preload("res://Samples/ArtDirection/Runtime/InariGroundSnap.gd")
const Teleport = preload("res://Samples/ArtDirection/Runtime/InariTeleport.gd")
const Ceiling = preload("res://Samples/ArtDirection/Runtime/InariCeiling.gd")
const Climb = preload("res://Samples/ArtDirection/Runtime/InariClimb.gd")
const JumpCorner = preload("res://Samples/ArtDirection/Runtime/InariJumpCorner.gd")
const GravityMotion = preload("res://Samples/ArtDirection/Runtime/InariGravityMotion.gd")
const EnemyContact = preload("res://Samples/ArtDirection/Runtime/InariEnemyContact.gd")
const AirAttack = preload("res://Samples/ArtDirection/Runtime/InariAirAttack.gd")
const GROUND_MASK := Collision.SOLID
const PLATFORM_MASK := Collision.ONE_WAY

@export_enum("metal", "wood") var audio_surface := "metal"
@export var story_mode := false
## Empty selects the original source skin for reference/controller probes.
@export_file("*.json") var appearance_path := ""

# Source profiles stay in Unity units; scene-facing values below use pixels.
var tuning: Dictionary
var physics: Dictionary
var combat: Dictionary
var units := 16.0
var gravity := 0.0
var jump_speed := 0.0
var min_jump_speed := 0.0

var audio := Audio.new()
var damage := Damage.new()
var targeting := Targeting.new()
var weak_dash := WeakDash.new()
var aim_time := AimTime.new()
var movement_input := MovementInput.new()
var stamina_feedback := StaminaFeedback.new()
var wind_buff := WindBuff.new()
var wind_trail := WindTrail.new()
var ground_snap := GroundSnap.new()
var jump_corner := JumpCorner.new()
var climb := Climb.new()
var ceiling := Ceiling.new()
var teleport := Teleport.new()
var gravity_motion := GravityMotion.new()
var enemy_contact := EnemyContact.new()
var air_attack := AirAttack.new()
var source_slide_bodies: Array[Object] = []
var source_touched_floor := false
var source_touched_ceiling := false
var source_landed := false
var source_time_scale := 1.0
var checkpoint := Vector2.ZERO
## A zero direction preserves legacy route checkpoints; native saves carry facing.
var checkpoint_facing := 0.0
var checkpoint_source := ""
var sprite := Animator.new()
var body_shape := CollisionShape2D.new()
var body_size := Vector2.ZERO
var facing := 1.0
var idle_clip := "idle"
var stamina := 0.0

# Contact state survives between physics steps, including grace periods.
var curve_time := 0.0
var coyote_time := 0.0
var wall_hold_time := 0.0
var wall_jump_time := 0.0
var wall_jump_x := 0.0
var can_air_jump := true
var can_air_attack := true
var jump_held := false
var climbing := false
var ceiling_hang := false:
	set(value):
		var was_hanging := ceiling_hang
		ceiling_hang = value
		if was_hanging and not value:
			ceiling.restore_upright()
var drop_time := 0.0
var dead := false

# Absolute deadlines keep input buffers independent of animation playback speed.
var clock := 0.0
var dash_ready_at := 0.0
var heavy_ready_at := 0.0
var attack_index := 0
var attack_buffer_until := 0.0
var throw_buffer_until := 0.0
var teleport_buffer_until := 0.0
var attack_info: Dictionary = {}
var hit_emitted := false
var action_state := "":
	set(value):
		if action_state == "attack_air" and value != action_state:
			air_attack.leave()
		action_state = value

# Dash interpolates position; Attack/Hit use a separate gravity velocity driver.
var path_start := Vector2.ZERO
var path_target := Vector2.ZERO
var path_curve: Dictionary = {}
var path_time := 0.0
var path_duration := 0.0
var path_collision_type := "Dash"

var projectile := KunaiVisual.new()
var projectile_flight: Node2D
var projectile_velocity := Vector2.ZERO
var projectile_normal := Vector2.ZERO
var projectile_active := false
## Source CreateShuriken captures the region bonus once for this projectile.
var shuriken_range := preload("res://Samples/INARIMechanisms/Devices/ShurikenDistance/ShurikenRange.gd").new()
var projectile_additive_distance := 0.0
var projectile_range_pixels: float:
	get:
		return (float(combat.get("ShurikenMaxDistance", 0.0)) + projectile_additive_distance) * units
var projectile_stuck := false
var projectile_target: Node
var projectile_local_pose := Transform2D.IDENTITY
var projectile_surface: WeakRef
var projectile_surface_pose := Transform2D.IDENTITY
var interaction_target: Node
var last_aim := Vector2.RIGHT


func _ready() -> void:
	tuning = Assets.read_json(Assets.ROOT + "controls.json")
	physics = tuning.physics
	combat = tuning.combat
	shuriken_range.settings = shuriken_range.settings.duplicate(true)
	shuriken_range.settings.base_distance = float(combat.ShurikenMaxDistance)
	shuriken_range.settings.pixels_per_unit = float(tuning.pixels_per_unit)
	add_child(shuriken_range)
	wind_buff.actor = self
	aim_time.configure(self)
	units = float(tuning.pixels_per_unit)
	Controls.install(tuning.bindings)
	movement_input.configure()

	# These equations and the hold/release behavior match PlayerStateMachine.
	gravity = 2.0 * float(physics.maxJumpHeight) / pow(float(physics.timeToJumpApex), 2) * units
	jump_speed = gravity * float(physics.timeToJumpApex)
	min_jump_speed = sqrt(2.0 * gravity * float(physics.minJumpHeight) * units)
	body_size = Vector2(tuning.body_size.x, tuning.body_size.y) * units
	ground_snap.configure(self)
	jump_corner.configure(self)
	climb.configure(self)
	ceiling.configure(self)
	teleport.configure(self)
	gravity_motion.configure(self)
	enemy_contact.configure(self)
	air_attack.configure(self)
	stamina = float(combat.MaxStamina)
	wall_hold_time = float(physics.WallHoldingTime)

	var rectangle := RectangleShape2D.new()
	rectangle.size = body_size
	body_shape.shape = rectangle
	body_shape.position.y = -body_size.y / 2.0
	add_child(body_shape)
	collision_layer = 2
	collision_mask = GROUND_MASK | PLATFORM_MASK
	safe_margin = ground_snap.skin
	floor_snap_length = safe_margin * 2.0

	var gfx: Dictionary = tuning.gfx_offset
	sprite.body_origin = body_shape.position
	sprite.pose_offset = body_shape.position + Vector2(gfx.x, -float(gfx.y)) * units
	sprite.appearance_path = appearance_path
	sprite.wall_origin = Vector2(body_size.x * 0.5, 0.0)
	sprite.ceiling_origin = body_shape.position - Vector2(0.0, body_size.x * 0.5)
	add_child(sprite)
	add_child(stamina_feedback)
	stamina_feedback.configure(self)
	add_child(wind_trail)
	wind_trail.configure(self)
	add_child(audio)
	projectile.top_level = true
	projectile.hide()
	add_child(projectile)
	damage.configure(self)
	targeting.configure(self)


func set_appearance(path: String) -> void:
	appearance_path = path
	sprite.set_appearance(path)


func _input(event: InputEvent) -> void:
	movement_input.input_event(event)
	targeting.input_event(event)


func input_action(name: String) -> StringName:
	return Controls.action(name)


func on_source_time_scale(value: float) -> void:
	source_time_scale = value


func _pressed(name: String) -> bool:
	return Input.is_action_just_pressed(input_action(name))


func _axis(negative: String, positive: String) -> float:
	var direction := movement_input.read_direction()
	return direction.x if negative == "left" and positive == "right" else direction.y


func _physics_process(delta: float) -> void:
	clock += delta
	wind_buff.advance(delta)
	damage.advance(delta)
	sprite.facing = air_attack.visual_facing if air_attack.active else facing
	var previous_frame := floori(sprite.elapsed * 60.0)
	sprite.advance(delta * source_time_scale)
	_play_animation_sounds(previous_frame)
	climb.advance(delta * source_time_scale)

	if dead:
		if sprite.finished():
			respawn()
		return

	stamina = minf(
		float(combat.MaxStamina),
		stamina + float(combat.StaminaIncreaseAmount) * delta * source_time_scale
	)
	aim_time.update()
	if weak_dash.active():
		_update_projectile(delta)
		targeting.step(get_global_mouse_position())
		weak_dash.step(delta, _axis("left", "right"))
		return

	coyote_time = maxf(0.0, coyote_time - delta * source_time_scale)
	wall_jump_time = maxf(0.0, wall_jump_time - delta * source_time_scale)
	drop_time = maxf(0.0, drop_time - delta)
	set_collision_mask_value(3, drop_time <= 0.0)
	_update_projectile(delta)
	targeting.step(get_global_mouse_position())

	var horizontal := _axis("left", "right")
	var vertical := _axis("up", "down")
	_read_actions(horizontal, vertical)
	if dead:
		return
	if weak_dash.active():
		weak_dash.step(delta, horizontal)
		return

	var was_grounded := is_on_floor()
	var movement_delta := delta * source_time_scale
	if movement_delta <= 0.0:
		return
	if path_time < path_duration:
		_follow_motion_curve(movement_delta, horizontal)
	else:
		_move_normally(movement_delta, horizontal, vertical)

	_update_contacts(was_grounded, horizontal)
	_finish_action()
	_update_locomotion_animation(horizontal, vertical)


func _read_actions(horizontal: float, vertical: float) -> void:
	# Source Interactive dispatches to the currently overlapped Trigger.
	if _pressed("interact") and is_instance_valid(interaction_target):
		interaction_target.interact(self)
	# A visual-study excerpt can supply a native conversation idle. It ends on
	# the first gameplay input; the controller still processes that same frame.
	if idle_clip != "idle":
		if horizontal != 0.0 or vertical != 0.0:
			idle_clip = "idle"
		for action: String in Controls.BUTTON_ACTIONS.values():
			if _pressed(action):
				idle_clip = "idle"
	if _pressed("cancel_projectile") and action_state != "throw":
		_retire_projectile()
	if _pressed("teleport"):
		teleport_buffer_until = clock + float(combat.ShurikenDashBufferTime)
		try_teleport()

	var pad_throw := _pressed("pad_throw")
	if _pressed("throw") or pad_throw:
		if pad_throw and projectile_active:
			teleport_buffer_until = clock + float(combat.ShurikenDashBufferTime)
			try_teleport()
		elif action_state != "throw":
			throw_buffer_until = clock + float(combat.ShurikenThrowBufferTime)
			if not action_state.begins_with("attack"):
				throw_projectile(_aim_direction(pad_throw))

	if _pressed("dash") and clock >= dash_ready_at:
		if not climbing or horizontal != facing:
			_start_dash(horizontal)

	if action_state == "dash" or action_state == "spawn":
		return

	if _pressed("jump"):
		_jump(vertical)
	if Input.is_action_just_released(input_action("jump")):
		jump_held = false
		velocity.y = maxf(velocity.y, -min_jump_speed)

	if _pressed("attack"):
		if is_instance_valid(targeting.current):
			weak_dash.start(targeting.current)
			return
		if action_state == "attack":
			attack_buffer_until = clock + float(attack_info.InputBuffer)
		elif is_on_floor():
			_start_attack(0)
		elif can_air_attack:
			_start_attack(0, true)

	if _pressed("heavy_attack") and is_on_floor() and clock >= heavy_ready_at:
		_start_attack(0, false, true)


func _move_normally(delta: float, horizontal: float, vertical: float) -> void:
	# Native LateUpdate bypasses normal movement while hanging from a ceiling.
	# An expired wall-hold clock alone therefore does not release a ceiling hold.
	if ceiling_hang and climb.settings.ceiling_skips_normal_movement:
		return
	var seated := is_on_floor() and vertical > 0.0 and action_state.is_empty()
	var axis := 0.0 if seated else horizontal
	var smoothing := float(
		physics.accelerationTimeGrounded if is_on_floor() else physics.accelerationTimeAirborne
	)
	if smoothing > 0.0:
		curve_time = clampf(
			curve_time + (1.0 if axis != 0.0 else -1.0) * delta / smoothing, 0.0, 1.0
		)
	else:
		curve_time = 1.0 if axis != 0.0 else 0.0

	# Both shipped horizontal curves are constant 1: start/stop are immediate.
	# Keep curve evaluation so a reimported source profile remains authoritative.
	var source_velocity := (
		facing * float(physics.moveSpeed) * units if axis == 0.0 and curve_time > 0.0 else 0.0
	)
	var target_velocity := axis * (float(physics.moveSpeed) + wind_buff.extra_speed) * units
	var curve: Dictionary = (
		physics.accelerationCurve if axis != 0.0 else physics.deAccelerationCurve
	)
	velocity.x = lerpf(source_velocity, target_velocity, Curves.evaluate(curve, curve_time))
	velocity.y = minf(
		-float(physics.MaxFallSpeed) * units,
		(
			velocity.y
			+ gravity * delta * (float(physics.decreaseJumpHoldingScale) if jump_held else 1.0)
		)
	)

	if wall_jump_time > 0.0:
		velocity.x = wall_jump_x
	elif climbing:
		velocity.x = facing * safe_margin / delta
		if wall_hold_time > 0.0:
			velocity.y = (
				vertical
				* float(physics.WallUpSpeed if vertical < 0.0 else physics.WallDownSpeed)
				* units
			)
		else:
			velocity.y = minf(velocity.y, float(physics.maxWallSlidingSpeed) * units)

	if action_state == "attack" or action_state == "heavy_attack" or action_state == "spawn":
		velocity.x = 0.0
	elif horizontal != 0.0 and not climbing and wall_jump_time <= 0.0:
		facing = horizontal

	move_source_velocity()


func move_source_velocity() -> void:
	_clear_move_contacts()
	if source_time_scale <= 0.0:
		return
	# Godot integrates with the real physics step. Unity PlayerCollision2D
	# receives scaled displacement, then returns velocity divided by that scale.
	velocity *= source_time_scale
	_move_source_body(velocity)
	velocity /= source_time_scale
	velocity = enemy_contact.after_move(
		velocity, get_physics_process_delta_time() * source_time_scale
	)


func move_source_offset(amount: Vector2) -> void:
	# JumpAttack.Exit passes an explicit displacement and ignores Move's return.
	# The offset itself is independent of TimeScale; contact callbacks can reset Y.
	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		return
	var retained := velocity
	_clear_move_contacts()
	velocity = amount / delta
	_move_source_body(retained * source_time_scale)
	enemy_contact.after_move(Vector2.ZERO, delta * source_time_scale)
	velocity = retained
	if source_touched_floor or (source_touched_ceiling and retained.y < 0.0):
		velocity.y = 0.0


func _clear_move_contacts() -> void:
	source_slide_bodies.clear()
	source_touched_floor = false
	source_touched_ceiling = false
	source_landed = false


func _move_source_body(callback_velocity: Vector2) -> void:
	gravity_motion.refresh_ray_origins()
	var was_grounded := is_on_floor()
	var origin := global_position
	var intended := velocity
	climb.before_move(intended, get_physics_process_delta_time())
	# Native horizontal rays ignore Platform. Godot's one-way shapes can still
	# return a diagonal corner normal while a stationary wall hold pushes into
	# them; that must not detach a passenger from an ascending wall. Downward
	# movement retains the platform mask so the character can land normally.
	set_collision_mask_value(3, drop_time <= 0.0 and (not climbing or velocity.y > 0.0))
	move_and_slide()
	jump_corner.after_move(origin, intended, callback_velocity, get_physics_process_delta_time())
	_record_move_contacts(was_grounded)


func _record_move_contacts(was_grounded: bool) -> void:
	# Enemy separation makes a second move. Preserve interactions from both
	# moves because Godot replaces its slide list on every move_and_slide call.
	source_touched_floor = source_touched_floor or is_on_floor()
	source_touched_ceiling = (
		source_touched_ceiling or (is_on_ceiling() and not jump_corner.adjusted)
	)
	source_landed = source_landed or (not was_grounded and is_on_floor())
	for index in get_slide_collision_count():
		var body := get_slide_collision(index).get_collider()
		if is_instance_valid(body) and body not in source_slide_bodies:
			source_slide_bodies.append(body)


func _jump(vertical: float) -> void:
	if is_on_floor() and vertical > 0.0:
		# Drop only through imported one-way platforms, never through solid terrain.
		drop_time = 0.2
		position.y += safe_margin * 2.0
		return

	var begins_hold := true
	if ceiling_hang:
		air_attack.leave()
		ceiling_hang = false
		velocity.y = 0.0
	elif climbing:
		air_attack.leave()
		climbing = false
		facing *= -1.0
		wall_jump_time = float(physics.WallClimbJumpTime)
		wall_jump_x = facing * float(physics.WallClimbJump.x) * units
		velocity = Vector2(wall_jump_x, -float(physics.WallClimbJump.y) * units)
		can_air_jump = true
		sprite.play("jump", true)
		audio.play("wall_jump")
	elif is_on_floor() or coyote_time > 0.0:
		air_attack.leave()
		velocity.y = -jump_speed
		coyote_time = 0.0
		sprite.play("jump", true)
		audio.play("jump")
	elif can_air_jump:
		air_attack.leave()
		velocity.y = -jump_speed * float(physics.airJumpScale)
		can_air_jump = false
		sprite.play("double_jump", true)
		audio.play("double_jump")
		# OnAirJumpUp resets velocity, but does not re-enable isJumpHolding.
		begins_hold = false
	else:
		return

	if begins_hold:
		jump_held = true
	action_state = ""
	path_time = path_duration


func _start_dash(horizontal: float) -> void:
	air_attack.leave()
	if horizontal != 0.0:
		facing = horizontal
	elif climbing or ceiling_hang:
		facing *= -1.0

	climbing = false
	ceiling_hang = false
	wall_jump_time = 0.0
	attack_info.clear()
	action_state = "dash"
	dash_ready_at = clock + float(combat.DashCoolTime)
	var duration := float(physics.dashFrame) * float(tuning.fixed_timestep)
	_start_motion(float(physics.dashDistance) * units, duration, physics.dashPhysicsCurve)
	sprite.play("dash", true)
	audio.play("dash")


func _start_motion(
	distance: float, duration: float, curve: Dictionary, collision_type := "Dash"
) -> void:
	climbing = false
	ceiling_hang = false
	wall_hold_time = float(physics.WallHoldingTime)
	path_start = position
	path_target = position + Vector2(facing * distance, 0.0)
	path_curve = curve
	path_time = 0.0
	path_duration = duration
	path_collision_type = collision_type
	velocity = Vector2.ZERO
	curve_time = 0.0


func _follow_motion_curve(delta: float, horizontal: float) -> void:
	if path_collision_type in gravity_motion.settings.collision_types:
		gravity_motion.step(delta, horizontal)
		return
	path_time = minf(path_duration, path_time + delta)
	var desired := path_start.lerp(
		path_target, Curves.evaluate(path_curve, path_time / path_duration)
	)
	var movement := desired - position
	var continuation := float(physics.moveSpeed) * units * delta
	if horizontal == facing and absf(movement.x) < continuation:
		movement.x = facing * continuation
		path_target.x += movement.x

	velocity = movement / delta
	ground_snap.restore_contact()
	move_source_velocity()
	# The native DirectionMove branch snaps to static terrain after displacement.
	# Weak-point DashAttack has its own driver and deliberately skips this call.
	ground_snap.apply_to_curve()
	if action_state == "dash":
		for body in source_slide_bodies:
			if body.has_method("receive_study_hit"):
				body.receive_study_hit({"interaction": 2}, facing)

	if path_time >= path_duration:
		velocity = Vector2(horizontal * float(physics.moveSpeed) * units, 0.0)
		curve_time = 1.0 if horizontal != 0.0 else 0.0


func _update_contacts(was_grounded: bool, horizontal: float) -> void:
	if is_on_floor():
		can_air_jump = true
		can_air_attack = true
		climbing = false
		ceiling_hang = false
		if not was_grounded:
			wall_hold_time = float(physics.WallHoldingTime)
		if not was_grounded and action_state.is_empty():
			sprite.play("landing", true)
			audio.play("land_" + audio_surface)
	elif was_grounded and velocity.y >= 0.0:
		coyote_time = float(physics.CoyoteTimeFrame) * float(tuning.fixed_timestep)

	if is_on_wall() and velocity.y >= 0.0 and wall_jump_time <= 0.0 and action_state.is_empty():
		for index in get_slide_collision_count():
			var hit := get_slide_collision(index)
			if absf(hit.get_normal().x) < 0.9:
				continue
			if hit.get_collider().get_meta("climbable", true):
				if not climbing:
					audio.play("wall_hang")
				climbing = true
				facing = -signf(hit.get_normal().x)
				can_air_attack = true

	if climbing and not is_on_wall():
		climbing = false
		if velocity.y < 0.0:
			# The original controller pulls the actor over the upper corner.
			wall_jump_time = float(physics.WallClimbJumpTime)
			wall_jump_x = facing * float(physics.WallClimbUpJump.x) * units
			velocity = Vector2(wall_jump_x, -float(physics.WallClimbUpJump.y) * units)

	if horizontal != 0.0 and is_on_floor() and action_state.is_empty():
		facing = horizontal


func _start_attack(index: int, airborne := false, heavy := false) -> void:
	air_attack.leave()
	attack_index = index
	attack_buffer_until = 0.0
	throw_buffer_until = 0.0
	hit_emitted = false
	climbing = false
	ceiling_hang = false
	var attacks: Dictionary = tuning.attacks.AttackInfo
	var clip := "attack%d" % (index + 1)
	action_state = "attack"
	# Runtime cleanup clears this dictionary; never alias the source tuning.
	attack_info = attacks.AttackInfos[index].duplicate(true)

	if airborne:
		action_state = "attack_air"
		clip = "jump_attack"
		attack_info = attacks.JumpAttackInfos[0].duplicate(true)
		can_air_attack = false
	elif heavy:
		action_state = "heavy_attack"
		clip = "heavy_attack"
		attack_info = attacks.StrongAttackInfos[0].duplicate(true)
		heavy_ready_at = clock + float(attack_info.PostBuffer)
		audio.play("heavy_attack")

	var movement: Dictionary = attack_info.AttackMovementInfo
	if airborne:
		air_attack.enter()
	elif not gravity_motion.attack_enemy_contact():
		# Source skips only ApplyAttackMovement when the body overlaps Enemy.
		# Do not cancel animation, damage, or overwrite a previous motion driver.
		_start_motion(
			float(movement.Distance) * units, float(movement.Time), movement.Curve, "Attack"
		)
	sprite.play(clip, true)


func _finish_action() -> void:
	if not attack_info.is_empty() and not hit_emitted:
		var check: Dictionary = attack_info.AttackCheckInfo
		if sprite.elapsed * 60.0 >= float(check.AttackCheckStartFrame):
			hit_emitted = true
			if action_state not in ["heavy_attack", "attack_air"]:
				audio.play("attack3" if attack_index == 2 else "attack")
			attacked.emit(attack_info)
			_deliver_attack(check)

	if action_state.is_empty() or not sprite.finished() or path_time < path_duration:
		return
	if action_state == "attack_air" and not air_attack.can_finish():
		return

	if action_state == "attack" and attack_index < 2 and attack_buffer_until > clock:
		_start_attack(attack_index + 1)
		return

	var previous := action_state
	action_state = ""
	attack_info.clear()
	if throw_buffer_until > clock and previous.begins_with("attack"):
		throw_projectile(_aim_direction())
	elif previous == "dash" and is_on_floor():
		sprite.play("dash_idle" if _axis("left", "right") == 0.0 else "dash_run")


func _deliver_attack(check: Dictionary) -> void:
	var area := RectangleShape2D.new()
	area.size = Vector2(check.AttackRange.x, check.AttackRange.y) * units
	var offset := (
		Vector2(float(check.AttackOffset.x) * facing, -float(check.AttackOffset.y)) * units
	)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = area
	query.transform = Transform2D(0.0, global_position + body_shape.position + offset)
	query.collision_mask = Collision.DAMAGEABLE
	query.collide_with_areas = true

	var delivered: Dictionary = {}
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
		if hit.collider.has_method("receive_study_hit"):
			if delivered.has(hit.collider):
				continue
			delivered[hit.collider] = true
			var payload := attack_info.duplicate()
			payload.interaction = 8 if action_state == "heavy_attack" else 4
			payload.source_actor = self
			if action_state == "heavy_attack" and hit.collider is CharacterBody2D:
				stamina_feedback.trigger(wind_buff.level, wind_buff.previous_level)
			var accepted: Variant = hit.collider.receive_study_hit(payload, facing)
			if hit.collider is CharacterBody2D and accepted == true:
				restore_stamina(float(attack_info.AddStamina))


func restore_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, float(combat.MaxStamina))


func _aim_direction(prefer_gamepad := false) -> Vector2:
	if prefer_gamepad or targeting.using_gamepad:
		last_aim = targeting.throw_direction()
		return last_aim

	var direction := get_global_mouse_position() - (global_position + body_shape.position)
	if direction.length_squared() > 1.0:
		last_aim = direction.normalized()
	return last_aim


func throw_projectile(direction: Vector2) -> void:
	air_attack.leave()
	_retire_projectile()
	throw_buffer_until = 0.0
	projectile_active = true
	projectile_additive_distance = shuriken_range.capture_bonus()
	projectile.global_transform = Transform2D(
		direction.angle(), global_position + body_shape.position
	)
	projectile_velocity = (
		direction.normalized()
		* float(tuning.projectile.MoveSpeed)
		* units
		/ float(tuning.projectile_body.m_Mass)
	)
	projectile.rotation = direction.angle()
	projectile.reset_pose(units)
	projectile.show()
	projectile_flight = KunaiEffects.start_flight(weak_dash.stage, projectile)
	audio.play("throw")

	var pose := "stand" if is_on_floor() else "jump"
	if is_on_floor() and _axis("left", "right") != 0.0:
		pose = "runfront" if signf(direction.x) == facing else "runback"
	var height := "level"
	if absf(direction.y) > absf(direction.x):
		height = "up" if direction.y < 0.0 else "down"
	var clip := "throw_%s_%s" % [pose, height]
	if climbing:
		clip = "wall_throw"
	elif ceiling_hang:
		clip = "ceiling_throw"
	elif not is_on_floor():
		velocity.y = -float(combat.ShurikenAiringDistance) * units

	if not climbing and direction.x != 0.0:
		facing = signf(direction.x)
	action_state = "throw"
	path_time = path_duration
	sprite.play(clip, true)


func _update_projectile(delta: float) -> void:
	if not projectile_active:
		return
	if not _sync_projectile_surface():
		return
	if projectile_target != null:
		if not is_instance_valid(projectile_target) or projectile_target.dead:
			_clear_projectile()
			return
		projectile.global_transform = (
			projectile_target.kunai.attachment_transform() * projectile_local_pose
		)
	if shuriken_range.exceeds_limit(
		projectile.global_position, global_position + body_shape.position, projectile_range_pixels
	):
		_clear_projectile()
		return
	if projectile_stuck:
		return

	var start := projectile.global_position
	var end := start + projectile_velocity * delta
	var query := PhysicsRayQueryParameters2D.create(
		start, end, Collision.PROJECTILE_SURFACE | Collision.DAMAGEABLE
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		projectile.global_position = end
		return
	projectile.global_position = hit.position
	KunaiEffects.stop_flight(projectile_flight)
	projectile_flight = null
	if hit.collider.has_method("receive_study_kunai"):
		if not hit.collider.dead and hit.collider.data.kunai.canShurikenHit:
			KunaiEffects.stick(weak_dash.stage, projectile)
		if not hit.collider.receive_study_kunai(self):
			audio.play("bounce")
			KunaiEffects.bounce(weak_dash.stage, projectile)
			_clear_projectile()
			return
		projectile_target = hit.collider
		projectile.global_position = hit.position
		# EnemyShurikenComponent embeds the blade halfway towards the center,
		# then parents it to GFX so it follows both movement and later flips.
		var center: Vector2 = (
			projectile_target.global_position + projectile_target.body_shape.position
		)
		projectile.global_position.x = lerpf(projectile.global_position.x, center.x, 0.5)
		projectile_local_pose = (
			projectile_target.kunai.attachment_transform().affine_inverse()
			* projectile.global_transform
		)
		projectile_stuck = true
		if teleport_buffer_until > clock:
			try_teleport()
		return

	if not hit.collider.get_meta("climbable", true):
		audio.play("bounce")
		KunaiEffects.bounce(weak_dash.stage, projectile)
		_clear_projectile()
		return

	projectile.global_position = hit.position
	projectile_normal = hit.normal
	projectile_stuck = true
	projectile_surface = weakref(hit.collider)
	projectile_surface_pose = (
		hit.collider.global_transform.affine_inverse() * projectile.global_transform
	)
	audio.play("stick")
	KunaiEffects.stick(weak_dash.stage, projectile)
	if teleport_buffer_until > clock:
		try_teleport()


func try_teleport() -> bool:
	if not _sync_projectile_surface():
		return false
	if not projectile_active or not projectile_stuck or stamina < float(combat.StaminaDefaultCost):
		return false

	var cost := float(combat.StaminaDefaultCost)
	var entity_hit := is_instance_valid(projectile_target)
	if entity_hit:
		if projectile_target.dead:
			_clear_projectile()
			return false
		cost = float(projectile_target.data.common.StaminaCost)
		if stamina < cost:
			return false

	# ShurikenDashPatter.Enter calls PhysicsReset before obtaining the destination.
	air_attack.leave()
	climbing = false
	ceiling_hang = false
	velocity = Vector2.ZERO
	curve_time = 0.0
	path_time = path_duration
	wall_jump_time = 0.0
	can_air_jump = true
	can_air_attack = true
	wall_hold_time = float(physics.WallHoldingTime)
	var origin := global_position
	var destination := projectile.global_position
	if projectile_surface != null:
		var surface: Node = projectile_surface.get_ref()
		if is_instance_valid(surface) and surface.has_method("study_kunai_destination"):
			destination = surface.study_kunai_destination(self, destination)
	if entity_hit:
		destination = projectile_target.kunai.destination(self)
	camera_shake_requested.emit("ShurikenDash")
	if entity_hit:
		projectile_target.kunai.dash(self)
	teleport.apply(destination, entity_hit)
	sprite.facing = facing

	stamina -= cost
	teleport_buffer_until = 0.0
	action_state = "teleport"
	attack_info.clear()
	sprite.play("teleport", true)
	audio.play("teleport")
	_clear_projectile()
	teleported.emit(origin, global_position)
	return true


func _retire_projectile() -> void:
	if projectile_active:
		var fade := KunaiFade.new()
		var stage: Node = weak_dash.stage
		var container: Node = stage if is_instance_valid(stage) else get_parent()
		container.add_child(fade)
		fade.configure(self, stage)
		if is_instance_valid(stage):
			stage.kunai_retired.emit(fade)
	_clear_projectile()


func _clear_projectile() -> void:
	KunaiEffects.stop_flight(projectile_flight)
	projectile_flight = null
	projectile_active = false
	projectile_stuck = false
	projectile_normal = Vector2.ZERO
	projectile_target = null
	projectile_surface = null
	projectile.hide()


func _sync_projectile_surface() -> bool:
	if projectile_surface == null:
		return true
	var surface: Node2D = projectile_surface.get_ref()
	if not is_instance_valid(surface):
		_clear_projectile()
		return false
	projectile.global_transform = surface.global_transform * projectile_surface_pose
	return true


func _exit_tree() -> void:
	KunaiEffects.stop_flight(projectile_flight)


func _play_animation_sounds(previous_frame: int) -> void:
	var key_frames: Array[int] = []
	var sound := ""
	if sprite.clip_name == "run":
		key_frames = [15, 35]
		sound = "step_" + audio_surface
	elif sprite.clip_name == "climb_up":
		key_frames = [3, 8]
		sound = "wall_up"
	else:
		return

	var length := maxi(1, roundi(float(sprite.clips[sprite.clip_name].length) * 60.0))
	for frame in range(previous_frame + 1, floori(sprite.elapsed * 60.0) + 1):
		if frame % length in key_frames:
			audio.play(sound)


func _update_locomotion_animation(horizontal: float, vertical: float) -> void:
	if not action_state.is_empty():
		return

	if climbing or ceiling_hang:
		sprite.play(climb.animation())
	elif not is_on_floor():
		if sprite.clip_name == "double_jump" and not sprite.finished():
			return
		sprite.play("jump" if velocity.y < 0.0 else "fall")
	elif vertical > 0.0:
		if sprite.clip_name not in ["sit", "sit_idle"]:
			sprite.play("sit")
		elif sprite.finished():
			sprite.play("sit_idle")
	elif horizontal != 0.0:
		sprite.play("run")
	elif (
		sprite.clip_name in ["landing", "dash_idle", "run_brake", "sit_finish"]
		and not sprite.finished()
	):
		return
	elif sprite.clip_name == "run":
		sprite.play("run_brake")
	elif sprite.clip_name in ["sit", "sit_idle"]:
		sprite.play("sit_finish")
	else:
		sprite.play(idle_clip)


func receive_damage(amount: float, knockback: Dictionary = {}) -> bool:
	var received := damage.receive(amount, knockback)
	if received:
		idle_clip = "idle"
	return received


func die(force := false) -> void:
	if dead or (not force and not damage.accepts_damage()):
		return
	air_attack.leave()
	weak_dash.cancel()
	aim_time.reset()
	dead = true
	targeting.reset()
	damage.mark_dead()
	velocity = Vector2.ZERO
	action_state = "dead"
	attack_info.clear()
	body_shape.set_deferred("disabled", true)
	_clear_projectile()
	sprite.play("dead", true)


func respawn() -> void:
	idle_clip = "idle"
	air_attack.leave()
	wind_buff.reset()
	weak_dash.cancel()
	aim_time.reset()
	targeting.reset()
	dead = false
	damage.reset()
	body_shape.set_deferred("disabled", false)
	ceiling.restore_upright(false)
	position = checkpoint
	if checkpoint_facing != 0.0:
		facing = checkpoint_facing
	velocity = Vector2.ZERO
	climbing = false
	ceiling_hang = false
	wall_jump_time = 0.0
	wall_hold_time = float(physics.WallHoldingTime)
	path_time = path_duration
	can_air_jump = true
	can_air_attack = true
	jump_held = false
	dash_ready_at = clock
	stamina = float(combat.MaxStamina)
	attack_info.clear()
	_clear_projectile()
	action_state = "spawn"
	sprite.play("spawn", true)
	audio.play("respawn")
	respawned.emit()
