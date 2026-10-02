extends RefCounted
## PlayerCollision2D adds a second base.Move after checking the first move's pose.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var settings: Dictionary


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "enemy_contact.json")


func after_move(returned_velocity: Vector2, scaled_delta: float) -> Vector2:
	if scaled_delta <= 0.0:
		return returned_velocity
	var shape := RectangleShape2D.new()
	shape.size = actor.body_size + Vector2.RIGHT * float(settings.extra_width) * actor.units
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, actor.body_shape.global_position)
	query.collision_mask = Collision.ENEMY_TARGET
	query.collide_with_areas = bool(settings.queries_hit_triggers)
	query.exclude = [actor.get_rid()]
	var hits := actor.get_world_2d().direct_space_state.intersect_shape(query, 1)
	if hits.is_empty():
		return returned_velocity
	# Native code looks up ONLY the first overlap's transform in GameManager;
	# it does not continue searching if that collider is not a registered enemy.
	var body: Object = hits[0].collider
	if not body.has_method("player_contact_info"):
		return returned_velocity
	var contact: Dictionary = body.player_contact_info()
	if contact.is_empty() or bool(contact.run_away):
		return returned_velocity
	var center: Vector2 = contact.center
	var difference: float = (actor.body_shape.global_position.x - center.x) / actor.units
	var weight := clampf(
		1.0 / maxf(absf(difference), float(settings.minimum_distance)),
		float(settings.weight_minimum),
		float(settings.weight_maximum)
	)
	var drag: float = (
		difference * actor.physics[settings.physics_profile_field] * weight * actor.units
	)
	# The shipped code adds unscaled drag to its returned displacement, but
	# applies drag * dt * TimeScale to the body. Preserve both distinct formulas.
	actor.velocity = Vector2(drag * actor.source_time_scale, 0)
	actor.gravity_motion.refresh_ray_origins()
	var was_grounded := actor.is_on_floor()
	actor.climb.before_move(actor.velocity, actor.get_physics_process_delta_time())
	actor.move_and_slide()  # Direct base move: never recurse through this helper.
	actor._record_move_contacts(was_grounded)
	return returned_velocity + Vector2(drag / scaled_delta, 0)
