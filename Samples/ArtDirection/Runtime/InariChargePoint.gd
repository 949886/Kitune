extends Node
## ShurikenChargePoint's fixed-step homing and real player overlap. Hidden-item
## fragments hide only their renderer after granting money, as in the source.
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
var source: Dictionary
var reward: Node
var visual: Node2D
var started := false
var finished := false
var received := false
var progress := 0.0
var speed := 0.0
var initial_direction := Vector2.ZERO
var source_time_scale := 1.0


func configure(record: Dictionary, owner_reward: Node) -> void:
	source = record
	reward = owner_reward
	visual = reward.stage.visuals_by_go[source.go]
	set_physics_process(false)


func activate() -> void:
	if started:
		return
	started = true
	speed = float(source.fields.MoveSpeed)
	assert(source.fields.isHidden, "This adapter currently covers hidden-reward fragments")
	# Source divides the random launch vector by StartVelocity on the next frame.
	# For hidden fragments its multiplication cancels, leaving these two samples.
	if reward.use_host_adapter:
		initial_direction = Vector2(
			reward.random.randf_range(-1.0, 1.0), -reward.random.randf_range(-1.0, 1.0)
		)
		source_time_scale = reward.host_time_scale
	else:
		initial_direction = Vector2(randf_range(-1.0, 1.0), -randf_range(-1.0, 1.0))
		reward.stage.combat_clock.subscribe(self)
	reward.stage.audio.play_event("reward_soul", visual)
	set_physics_process(true)


func on_source_time_scale(value: float) -> void:
	source_time_scale = value


func _physics_process(delta: float) -> void:
	if reward.use_host_adapter:
		if not reward.actor_alive.is_valid() or not bool(reward.actor_alive.call()):
			cancel()
			return
	elif reward.manager.player.dead:
		cancel()
		return
	var step := delta * source_time_scale
	var units: float = reward.host_units if reward.use_host_adapter else reward.manager.player.units
	var target: Vector2 = (
		reward.target_position.call()
		if reward.use_host_adapter
		else reward.manager.player.body_shape.global_position
	)
	var direction := (target - visual.global_position).normalized()
	var motion := initial_direction.lerp(direction, clampf(progress, 0.0, 1.0))
	progress += step
	speed = minf(speed + step, float(reward.manager.rules.charge_max_speed))
	visual.global_position += motion * speed * step * units
	if progress <= float(reward.manager.rules.charge_min_time):
		return
	var shape := CircleShape2D.new()
	shape.radius = float(source.fields.collisionRadius) * units
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, visual.global_position)
	query.collision_mask = reward.actor_layers if reward.use_host_adapter else Collision.PLAYER
	var hits := visual.get_world_2d().direct_space_state.intersect_shape(
		query, 32 if reward.use_host_adapter else 1
	)
	var captured := false
	for hit: Dictionary in hits:
		if not reward.use_host_adapter or reward.accept_actor.call(hit.collider):
			captured = true
			break
	if captured:
		finished = true
		received = true
		if reward.use_host_adapter:
			reward.currency_requested.emit(
				reward.manager.player, int(reward.manager.rules.charge_value)
			)
		else:
			reward.manager.session.money = (
				int(reward.manager.session.get("money", 0)) + int(reward.manager.rules.charge_value)
			)
		reward.stage.audio.play_event("reward_prism_get", visual)
		visual.hide()
		set_physics_process(false)


func cancel() -> void:
	started = true
	finished = true
	visual.hide()
	set_physics_process(false)
