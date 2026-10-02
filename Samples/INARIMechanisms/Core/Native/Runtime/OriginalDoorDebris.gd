extends RigidBody2D
## Original fragment geometry and rigid-body coefficients on Godot's contact solver.

const Collision = preload("StudyCollision.gd")
const UNITS := 16.0

var source_gravity := Vector2.ZERO
var source_linear_drag := 0.0
var source_angular_drag := 0.0
var contact_seen := false


func configure(source: Dictionary, settings: Dictionary, launch_velocity: Vector2) -> void:
	assert(source.m_Simulated and int(source.m_Constraints) in [0, 4])
	mass = float(source.m_Mass)
	lock_rotation = (int(source.m_Constraints) & 4) != 0
	can_sleep = int(source.m_SleepingMode) != 0
	continuous_cd = (
		CCD_MODE_DISABLED if int(source.m_CollisionDetection) == 0 else CCD_MODE_CAST_SHAPE
	)
	collision_layer = Collision.PARTICLE_SURFACE
	collision_mask = Collision.DOOR_DEBRIS_TARGET
	contact_monitor = true
	max_contacts_reported = 1
	custom_integrator = true
	source_gravity = (
		Vector2(settings.gravity.x, -settings.gravity.y) * UNITS * float(source.m_GravityScale)
	)
	source_linear_drag = float(source.m_LinearDrag)
	source_angular_drag = float(source.m_AngularDrag)
	linear_velocity = launch_velocity
	# InteractiveDoor assigns only linear velocity. Collision torque, rather
	# than an invented random initial spin, rotates the original polygons.
	angular_velocity = 0.0
	var surface := PhysicsMaterial.new()
	surface.friction = float(settings.fallback_material.friction)
	surface.bounce = float(settings.fallback_material.bounce)
	physics_material_override = surface


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Apply the imported gravity independently of the host project's gravity.
	# Damping uses Godot's linear adapter; Unity solver/frame differences remain.
	state.linear_velocity += source_gravity * state.step
	state.linear_velocity *= maxf(0.0, 1.0 - source_linear_drag * state.step)
	state.angular_velocity *= maxf(0.0, 1.0 - source_angular_drag * state.step)
	contact_seen = contact_seen or state.get_contact_count() > 0
