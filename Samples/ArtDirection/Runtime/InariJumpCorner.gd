extends RefCounted
## Source OnAbove / AdjustCornerOffsetOnJump, including Teleport's overlap search.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var source: Dictionary
var settings: Dictionary
var skin := 0.0
var spacing := 0.0
var adjusted := false


func configure(player: CharacterBody2D) -> void:
	actor = player
	source = player.ground_snap.settings
	settings = source.jump_corner
	skin = source.skin_width * player.units
	spacing = settings.vertical_ray_spacing * player.units


func after_move(
	origin: Vector2, intended: Vector2, callback_velocity: Vector2, delta: float
) -> void:
	adjusted = false
	if (
		intended.y >= 0.0
		or callback_velocity.y >= 0.0
		or actor.climbing
		or settings.ignored_states.has(actor.action_state)
	):
		return
	var count := int(settings.vertical_ray_count)
	var distance: float = -intended.y * delta + settings.ray_padding * actor.units
	var top_left := origin + Vector2(-actor.body_size.x * 0.5, -actor.body_size.y)
	top_left.x += actor.global_position.x - origin.x
	var left := false
	var right := false
	var above := false
	var clamped_y := 0.0
	for index in count:
		var start := top_left + Vector2(index * spacing, 0)
		var query := PhysicsRayQueryParameters2D.create(
			start, start + Vector2.UP * distance, Collision.SOLID
		)
		query.exclude = [actor.get_rid()]
		query.hit_from_inside = source.queries_start_in_colliders
		query.collide_with_areas = source.queries_hit_triggers
		var hit := actor.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var travel := start.distance_to(hit.position)
		clamped_y = -(travel - skin) if travel > 0.0 else 0.0
		distance = travel + skin
		above = true
		left = left or index == 0
		right = right or index == count - 1
	if not above or (left and right):
		return
	actor.global_position.y = origin.y + clamped_y
	var correction := Vector2((1.0 if left else -1.0) * spacing * count, 0)
	_teleport(actor.body_shape.global_position + correction)
	actor.gravity_motion.refresh_ray_origins()
	# The first Teleport clears moveAmount. OnAbove therefore adds a full upward
	# step at the shifted position, not just the unused part of the blocked step.
	_teleport(actor.body_shape.global_position + Vector2(0, callback_velocity.y * delta))
	# Teleport also clears the horizontal displacement returned by base.Move.
	actor.velocity = Vector2(0, callback_velocity.y)
	adjusted = true


func _teleport(center: Vector2) -> void:
	var result: Dictionary = actor.teleport.find_position(center, Collision.SOLID)
	actor.global_position = result.center - actor.body_shape.position
