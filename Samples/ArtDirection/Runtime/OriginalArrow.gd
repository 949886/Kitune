extends RigidBody2D
## Source Arrow: linear impulse, continuous collision, one player hit and immediate despawn.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const Glow = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const Trail = preload("res://Samples/ArtDirection/Runtime/OriginalArrowTrail.gd")
const UNITS := 16.0
const DATA_PATH := "res://Samples/ArtDirection/Original/INARI/Projectiles/arrow.json"

var source: Dictionary
var stage: Node2D
var visual: Sprite2D
var collision_shape: CollisionShape2D
var trail: Line2D
var flight_effect: Node2D
var hit := false
var launch_damage := 0
var shooter: Node2D


func configure(
	owner_stage: Node2D,
	point: Vector2,
	angle: float,
	speed: float,
	owner_actor: Node2D,
	damage: int
) -> void:
	stage = owner_stage
	source = Assets.read_json(DATA_PATH)
	shooter = owner_actor
	launch_damage = damage
	global_position = point
	global_rotation = angle
	var body: Dictionary = source.rigidbody
	assert(int(body.m_BodyType) == 0 and body.m_Simulated and int(body.m_Constraints) == 4)
	assert(float(body.m_GravityScale) == 0.0 and int(body.m_CollisionDetection) == 1)
	mass = float(body.m_Mass)
	gravity_scale = float(body.m_GravityScale)
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = float(body.m_LinearDrag)
	angular_damp = float(body.m_AngularDrag)
	lock_rotation = true
	# Continuous detection is handled by the exact circle sweep below. Native
	# shape CCD also produced false contacts in the imported tilemap fixture.
	continuous_cd = RigidBody2D.CCD_MODE_DISABLED
	collision_layer = Collision.ARROW
	collision_mask = Collision.ARROW_SURFACE | Collision.PLAYER
	contact_monitor = true
	max_contacts_reported = 1
	var collider: Dictionary = source.collider
	assert(collider.m_Enabled and not collider.m_IsTrigger)
	collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = float(collider.m_Radius) * UNITS
	collision_shape.shape = shape
	collision_shape.position = Vector2(collider.m_Offset.x, -collider.m_Offset.y) * UNITS
	add_child(collision_shape)
	_create_visual()
	body_entered.connect(_on_body_entered)
	apply_central_impulse(Vector2.from_angle(angle) * speed * UNITS)
	# Arrow's OnTimeScaleChanged is empty; its child system is not registered
	# through EffectPoolingManager.CreateObject either.
	flight_effect = stage.spawn_effect("ArrowFlight", point, angle, false, self, false)
	flight_effect.follow_rotation = true


func _create_visual() -> void:
	var data: Dictionary = source.visual
	visual = Sprite2D.new()
	visual.centered = false
	visual.texture = load(Assets.ROOT + "Projectiles/" + data.sprite.path)
	visual.offset = Assets.vec(data.sprite.offset)
	visual.transform = Assets.matrix(data.transform)
	visual.scale *= UNITS / float(data.sprite.ppu)
	visual.flip_h = data.flip[0]
	visual.flip_v = data.flip[1]
	visual.modulate = Assets.color(data.color)
	visual.z_as_relative = false
	visual.z_index = stage.sort_depth(data.sort)
	visual.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if int(data.sprite.filter) == 0
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	visual.material = ShaderMaterial.new()
	visual.material.shader = Glow
	MaterialSettings.configure(visual.material, data.material, get_viewport().use_hdr_2d)
	add_child(visual)
	trail = Trail.new()
	add_child(trail)
	trail.configure(visual, source.trail, stage.sort_depth)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if hit:
		state.linear_velocity = Vector2.ZERO
		return
	# Godot's native shape CCD misses the original subpixel circle against thin
	# walls. Sweep the same body geometry explicitly before its next integration.
	var query := PhysicsTestMotionParameters2D.new()
	query.from = state.transform
	query.motion = state.linear_velocity * state.step
	query.margin = 0.0
	query.recovery_as_collision = true
	var result := PhysicsTestMotionResult2D.new()
	if PhysicsServer2D.body_test_motion(get_rid(), query, result):
		var pose := state.transform
		pose.origin += result.get_travel()
		state.transform = pose
		state.linear_velocity = Vector2.ZERO
		_queue_hit(result.get_collider(), pose * collision_shape.position)


func _on_body_entered(body: Node) -> void:
	_queue_hit(body, collision_shape.global_position)


func _queue_hit(body: Node, center: Vector2) -> void:
	if hit:
		return
	hit = true
	# Defer scene mutations until the physics server finishes flushing contacts.
	_finish_hit.call_deferred(body, center)


func _finish_hit(body: Node, center: Vector2) -> void:
	if body is CollisionObject2D and body.collision_layer & Collision.PLAYER:
		# Projectile.ApplyDamage requests one HP regardless of Shoot's stored damage.
		body.receive_damage(float(source.damage))
	linear_velocity = Vector2.ZERO
	stage.spawn_effect(source.destroy_effect, center, 0.0, false, null, false)
	hide()
	if is_instance_valid(flight_effect):
		flight_effect.queue_free()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(flight_effect):
		flight_effect.queue_free()
