extends RefCounted
## Native two-corner StickToGround used after curve movement, excluding DashAttack.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var settings: Dictionary
var actor: CharacterBody2D
var maximum_distance := 0.0
var skin := 0.0
var pending_contact := false
var last_snap_found := false
var snapped_position := Vector2.ZERO


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "ground_snap.json")
	maximum_distance = float(settings.maximum_step_height) * actor.units
	skin = float(settings.skin_width) * actor.units


func apply_to_curve() -> Vector2:
	pending_contact = false
	if actor.path_collision_type not in settings.snap_collision_types:
		return Vector2.ZERO
	var correction := snap_to_ground(maximum_distance)
	if not last_snap_found:
		return Vector2.ZERO
	# Curve endpoints follow the corrected body; ordinary teleports do not.
	actor.path_start += correction
	actor.path_target += correction
	snapped_position = actor.global_position
	pending_contact = true
	return correction


func snap_to_ground(distance: float) -> Vector2:
	last_snap_found = false
	actor.gravity_motion.refresh_ray_origins()
	var bottom: Vector2 = actor.global_position
	var half_width: float = actor.body_size.x * 0.5
	var floor_y := INF
	for side in [-1.0, 1.0]:
		var origin := bottom + Vector2(side * half_width, 0)
		var query := PhysicsRayQueryParameters2D.create(
			origin, origin + Vector2.DOWN * distance, Collision.STATIC_SURFACE
		)
		query.exclude = [actor.get_rid()]
		# Unity's queriesStartInColliders includes a ray starting inside a shape.
		query.hit_from_inside = bool(settings.queries_start_in_colliders)
		query.collide_with_areas = bool(settings.queries_hit_triggers)
		var hit := actor.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			floor_y = minf(floor_y, hit.position.y)
	if is_inf(floor_y):
		return Vector2.ZERO

	# The source chooses the higher of the two foot-corner ground hits.
	last_snap_found = true
	var correction := Vector2(0, floor_y - bottom.y - skin)
	actor.global_position += correction
	return correction


func restore_contact() -> void:
	# Native Move checks the two below rays again on the following movement,
	# even when vertical displacement is zero. Godot otherwise retains an air
	# state after the explicit translation, until gravity resumes after the dash.
	if (
		pending_contact
		and actor.path_collision_type in settings.snap_collision_types
		and actor.global_position.is_equal_approx(snapped_position)
	):
		actor.apply_floor_snap()
	pending_contact = false
