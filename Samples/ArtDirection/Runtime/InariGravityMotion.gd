extends RefCounted
## Attack/Hit curves attenuate velocity; they are not position interpolation.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Curves = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var settings: Dictionary
var ray_bottom := Vector2.ZERO


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "gravity_motion.json")
	refresh_ray_origins()


func refresh_ray_origins() -> void:
	# Unity caches these at the start of Move, before translating the body.
	ray_bottom = actor.global_position


func attack_enemy_contact() -> bool:
	# PlayerAttackPattern and PlayerStrongAttackPattern test the body center,
	# not the forward attack range. An enemy behind the player also suppresses
	# new motion. The attack animation and hit check remain active.
	var contract: Dictionary = settings.attack_contact
	var extra: Dictionary = actor.combat[contract.size_profile_field]
	var shape := RectangleShape2D.new()
	shape.size = actor.body_size + Vector2(extra.x, extra.y) * actor.units
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(
		deg_to_rad(float(contract.angle)), actor.body_shape.global_position
	)
	query.collision_mask = Collision.ENEMY_TARGET
	query.collide_with_areas = bool(settings.queries_hit_triggers)
	query.exclude = [actor.get_rid()]
	return not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func step(delta: float, horizontal: float) -> void:
	if delta <= 0.0 or actor.source_time_scale <= 0.0:
		return
	# Collision2D.UpdateCollision advances a C# float before LateUpdate samples it.
	delta = float(PackedFloat32Array([delta])[0])
	actor.path_time = float(PackedFloat32Array([actor.path_time + delta])[0])
	actor.velocity.y += actor.gravity * delta
	var continuation: float = (
		horizontal * actor.physics.moveSpeed * actor.units * settings.extra_input_multiplier
	)
	if actor.path_time >= actor.path_duration:
		var retained := actor.velocity
		actor.velocity.x = continuation
		_move_body()
		# ResetDashMovement ignores Move's return; only contact callbacks reset Y.
		if actor.source_touched_floor or (actor.source_touched_ceiling and retained.y < 0.0):
			retained.y = 0.0
		actor.velocity = retained
		_finish()
		return

	var base_velocity: Vector2 = (actor.path_target - actor.path_start) / actor.path_duration
	var weight := clampf(
		Curves.evaluate(actor.path_curve, actor.path_time / actor.path_duration), 0, 1
	)
	var intended := Vector2(
		base_velocity.x * (1.0 - weight), base_velocity.y + actor.gravity * actor.path_time
	)
	if (
		actor.path_collision_type not in settings.no_extra_input_types
		and absf(horizontal) > float(settings.active_input_threshold)
	):
		intended.x += continuation
	actor.velocity = intended
	if actor.action_state == "heavy_attack" and wall_or_edge(intended * delta):
		actor.velocity.x = 0.0
	_move_body()
	# Native velocity is assigned AFTER Move, even when a wall/ground blocks it.
	actor.velocity = intended
	if actor.source_landed:
		# Collision2D.Land switches to Idle without cancelling the attack animation.
		_finish()


func _finish() -> void:
	actor.path_time = actor.path_duration
	actor.path_collision_type = "Idle"


func _move_body() -> void:
	# Godot's slope-stop heuristic discards very small X relative to downward Y.
	# Native ray movement retains this charge/attack tail even on flat ground.
	var stop_on_slope := actor.floor_stop_on_slope
	actor.floor_stop_on_slope = false
	actor.move_source_velocity()
	actor.floor_stop_on_slope = stop_on_slope


func wall_or_edge(displacement: Vector2) -> bool:
	# Source uses the full displacement magnitude, including gravity, for both
	# the horizontal wall ray and the ground lookahead. Mathf.Sign(0) is +1.
	var side := 1.0 if displacement.x >= 0.0 else -1.0
	var distance := displacement.length()
	var corner := Vector2(side * actor.body_size.x * 0.5, 0)
	var ahead := ray_bottom + corner + Vector2(side * distance, 0)
	# CheckWallandGround forms `ahead` BEFORE GetWallPoint refreshes the origins.
	refresh_ray_origins()
	var wall := _ray(ray_bottom + corner, Vector2(side * distance, 0), Collision.STATIC_SURFACE)
	if not wall.is_empty() and wall.collider.get_meta("source_layer", "") != "Door":
		return true
	var ground := _ray(
		ahead,
		Vector2.DOWN * float(settings.ground_check_distance) * actor.units,
		Collision.STATIC_SURFACE | Collision.INTERACTIVE_WALL
	)
	return ground.is_empty()


func _ray(origin: Vector2, displacement: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(origin, origin + displacement, mask)
	query.exclude = [actor.get_rid()]
	query.hit_from_inside = bool(settings.queries_start_in_colliders)
	query.collide_with_areas = bool(settings.queries_hit_triggers)
	return actor.get_world_2d().direct_space_state.intersect_ray(query)
