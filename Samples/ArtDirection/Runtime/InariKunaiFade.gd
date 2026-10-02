extends "res://Samples/ArtDirection/Runtime/InariKunaiVisual.gd"
## A dequeued native kunai keeps moving while its two independent tweens finish.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Effects = preload("res://Samples/ArtDirection/Runtime/InariKunaiEffects.gd")

var actor: WeakRef
var velocity := Vector2.ZERO
var stuck := false
var attachment: WeakRef
var attachment_pose := Transform2D.IDENTITY
var surface_attachment := false
var phase := "brighten"
var elapsed := 0.0
var initial_blend := 0.0
var initial_alpha := 1.0
var flight: Node2D
var source_stage: Node


func configure(player: Node, stage: Node) -> void:
	source_stage = stage
	var source: Dictionary = Assets.read_json(Assets.ROOT + "kunai_fade.json")
	assert(source.ease == "OutQuad" and source.next_tween_starts_next_update)
	actor = weakref(player)
	global_transform = player.projectile.global_transform
	modulate = player.projectile.modulate
	z_index = player.projectile.z_index
	velocity = player.projectile_velocity
	stuck = player.projectile_stuck
	# Retiring preserves the existing emitter and its world-space particle history.
	flight = player.projectile_flight
	player.projectile_flight = null
	if is_instance_valid(flight):
		flight.follow_actor = self
	if is_instance_valid(player.projectile_target):
		attachment = weakref(player.projectile_target)
		attachment_pose = player.projectile_local_pose
	elif player.projectile_surface != null:
		attachment = player.projectile_surface
		attachment_pose = player.projectile_surface_pose
		surface_attachment = true
	apply_material(self, stage.lighting if is_instance_valid(stage) else null)
	initial_blend = player.projectile.material.get_shader_parameter("hit_blend")
	initial_alpha = modulate.a
	material.set_shader_parameter("hit_blend", initial_blend)
	process_priority = 420


func _process(delta: float) -> void:
	advance_fade(delta)


func advance_fade(delta: float) -> void:
	if phase == "done":
		return
	# DOTween uses float time and defaults to OutQuad in the shipped player.
	elapsed = PackedFloat32Array([elapsed + delta])[0]
	var duration: float = (
		renderer.bright_duration if phase == "brighten" else renderer.fade_duration
	)
	var t := 1.0 if duration <= 0.0 else clampf(elapsed / duration, 0.0, 1.0)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	if phase == "brighten":
		material.set_shader_parameter("hit_blend", lerpf(initial_blend, 1.0, eased))
	else:
		modulate.a = initial_alpha * (1.0 - eased)
	if t < 1.0:
		return
	if phase == "brighten":
		# OnComplete creates the fade tween for the following DOTween update.
		phase = "fade"
		elapsed = 0.0
	else:
		finish()


func _physics_process(delta: float) -> void:
	advance_motion(delta)


func advance_motion(delta: float) -> void:
	if phase == "done":
		return
	if attachment != null:
		var target: Node = attachment.get_ref()
		if not is_instance_valid(target):
			finish()
			return
		global_transform = (
			(target.global_transform if surface_attachment else target.kunai.attachment_transform())
			* attachment_pose
		)
		return
	if stuck:
		return
	var end := global_position + velocity * delta
	var query := PhysicsRayQueryParameters2D.create(
		global_position, end, Collision.PROJECTILE_SURFACE | Collision.DAMAGEABLE
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = end
		return
	global_position = hit.position
	Effects.stop_flight(flight)
	flight = null
	velocity = Vector2.ZERO
	stuck = true
	var player: Node = actor.get_ref()
	if is_instance_valid(player) and hit.collider.has_method("receive_study_kunai"):
		if not hit.collider.dead and hit.collider.data.kunai.canShurikenHit:
			Effects.stick(source_stage, self)
		hit.collider.receive_study_kunai(player)
		var target: Node = hit.collider
		var center: Vector2 = target.global_position + target.body_shape.position
		global_position.x = lerpf(global_position.x, center.x, 0.5)
		attachment = weakref(target)
		attachment_pose = target.kunai.attachment_transform().affine_inverse() * global_transform
	elif (
		is_instance_valid(player)
		and hit.collider.get_meta("source_layer", "") in ["Ground", "Wall", "Door"]
	):
		player.audio.play("stick")
		Effects.stick(source_stage, self)
		attachment = weakref(hit.collider)
		attachment_pose = hit.collider.global_transform.affine_inverse() * global_transform
		surface_attachment = true
	# Native TryDestroyShuriken ignores further destroy requests while Destroying.
	# This object is never restored to the player's list of teleport destinations.


func finish() -> void:
	Effects.stop_flight(flight)
	flight = null
	phase = "done"
	hide()
	queue_free()


func _exit_tree() -> void:
	Effects.stop_flight(flight)
