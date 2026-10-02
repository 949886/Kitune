extends RefCounted
## Original hold clock and PlayerClimbState animation selection.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var settings: Dictionary
var ray_settings: Dictionary
var side_contact := false
var bottom_contact := false


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "climb.json")
	ray_settings = actor.ground_snap.settings


func advance(scaled_delta: float) -> void:
	# UpdateCollision runs in the air as well as on a wall. MultiThrow's
	# AllIgnore flag skips this update; merely changing walls never refills it.
	if settings.timer_ignored_states.has(actor.action_state):
		return
	if actor.wall_hold_time > 0.0:
		# The source field is a float; at the shipped 1,000,000 duration,
		# an ordinary 60 Hz decrement rounds back to the same value.
		actor.wall_hold_time = float(PackedFloat32Array([actor.wall_hold_time - scaled_delta])[0])


func before_move(intended: Vector2, delta: float) -> void:
	side_contact = false
	bottom_contact = false
	if actor.ceiling_hang:
		return
	var side: float = actor.facing
	if intended.x != 0.0 and not actor.climbing and actor.wall_jump_time <= 0.0:
		side = signf(intended.x)
	var travel := absf(intended.x * delta)
	var skin: float = actor.ground_snap.skin
	var distance: float = (
		settings.stationary_ray_distance * actor.units if travel < skin else travel + skin
	)
	var spacing: float = ray_settings.horizontal_ray_spacing * actor.units
	var origin: Vector2 = actor.global_position + Vector2(side * actor.body_size.x * 0.5, 0)
	# Preserve the bottom-to-top order and shrinking range. A nearer lower
	# obstruction may prevent a farther upper ray from recording a wall contact.
	for index in int(ray_settings.horizontal_ray_count):
		var start := origin + Vector2.UP * spacing * index
		var query := PhysicsRayQueryParameters2D.create(
			start, start + Vector2(side * distance, 0), Collision.SOLID
		)
		query.exclude = [actor.get_rid()]
		query.hit_from_inside = ray_settings.queries_start_in_colliders
		query.collide_with_areas = ray_settings.queries_hit_triggers
		var hit := actor.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_distance := start.distance_to(hit.position)
		if is_zero_approx(hit_distance):
			continue
		distance = hit_distance + skin
		side_contact = true
		bottom_contact = bottom_contact or index == 0


func animation() -> String:
	var above: bool = actor.is_on_ceiling() or actor.source_touched_ceiling
	if not above and actor.velocity.y < 0.0:
		return settings.clips.ClimbUp
	if not above and actor.velocity.y > 0.0:
		return settings.clips.ClimbDown
	if side_contact and not bottom_contact:
		return settings.clips.ClimbCorner
	return settings.clips.ClimbCeiling if actor.ceiling_hang else settings.clips.Climb
