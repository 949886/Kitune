extends Node
## Native Door toggles immediately; its invisible wall releases only after the
## opening state's normalized colliderTiming. Closing remains HardWall until
## another opening, matching the shipped coroutine's explicit Open-state wait.
signal state_changed(open: bool)
signal passability_changed(passable: bool)
signal attachments_invalidated(surfaces: Array[StaticBody2D])

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Animator = preload("res://Samples/ArtDirection/Runtime/InariMechanismAnimator.gd")
var source: Dictionary
var stage: Node
var player: Node
var animation := Animator.new()
var bodies: Array[StaticBody2D] = []
var is_open := false
var hard := false
var elapsed := 0.0
var release_at := INF
var invisible: StaticBody2D
var passable := false
var collision_layers := (
	Collision.SOLID
	| Collision.PROJECTILE_SURFACE
	| Collision.SIGHT_SURFACE
	| Collision.RAY_SURFACE
	| Collision.PARTICLE_SURFACE
	| Collision.STATIC_SURFACE
	| Collision.STUCK_SURFACE
	| Collision.ARROW_SURFACE
)


func configure(record: Dictionary, owner_stage: Node, actor: Node) -> void:
	source = record
	stage = owner_stage
	player = actor
	add_child(animation)
	animation.configure(record.animation, stage)
	is_open = bool(record.fields.isOpening)
	for data: Dictionary in record.colliders:
		var body := StaticBody2D.new()
		stage.add_child(body)
		body.transform = Assets.matrix(data.transform)
		body.set_meta("source_go", data.go)
		body.set_meta("source_origin", body.position)
		# Door.Start changes layers, not enabled state. The shipped upper leaf
		# collider stays disabled; only invisibleCollider gates this doorway.
		body.set_meta("source_enabled", bool(data.enabled))
		body.set_meta("source_layer", "Wall")
		body.set_meta("climbable", true)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Assets.vec(data.size)
		shape.shape = box
		shape.position = Assets.vec(data.offset)
		body.add_child(shape)
		bodies.append(body)
		if int(data.id) == int(record.fields.invisibleCollider.m_PathID):
			invisible = body
	var trigger := "Open" if is_open else "Close"
	animation.trigger(trigger)
	animation.tracks.advance(float(source.animation.states[animation.state].length))
	_set_layers()
	_sync_shapes()
	process_physics_priority = 250


func notify() -> void:
	is_open = not is_open
	hard = true
	elapsed = 0.0
	release_at = INF
	# DoorRoutine destroys kunai already attached to either moving leaf or
	# invisible wall. New hits bounce while its native layer is HardWall.
	attachments_invalidated.emit(bodies)
	if (
		is_instance_valid(player)
		and player.projectile_surface != null
		and player.projectile_surface.get_ref() in bodies
	):
		player._clear_projectile()
	var trigger := "Open" if is_open else "Close"
	animation.trigger(trigger)
	if is_open:
		var clip: Dictionary = source.animation.states[animation.state]
		var transition: Dictionary = source.animation.triggers.Open
		var blend := float(transition.m_TransitionDuration)
		if not transition.m_HasFixedDuration:
			blend *= float(clip.length)
		release_at = maxf(blend, float(clip.length) * float(source.fields.colliderTiming))
	stage.audio.play_event("door_gear_open" if is_open else "door_gear_close", self)
	_set_layers()
	state_changed.emit(is_open)


func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed >= release_at:
		release_at = INF
		hard = false
		_set_layers()
	_sync_shapes()


func _sync_shapes() -> void:
	for body: Node2D in bodies:
		var visual: Node2D = stage.visuals_by_go.get(body.get_meta("source_go"))
		if visual != null:
			body.position = body.get_meta("source_origin") + visual.animation_offset


func _set_layers() -> void:
	for body: StaticBody2D in bodies:
		body.collision_layer = collision_layers if body.get_meta("source_enabled") else 0
		body.set_meta("climbable", not hard)
		body.set_meta("source_layer", "HardWall" if hard else "Wall")
	# This collider is explicitly enabled/disabled by Door, independently of
	# its serialized enabled flag. Other leaf colliders retain their flags.
	invisible.collision_layer = 0 if is_open and not hard else collision_layers
	var accessible := is_open and not hard
	if accessible != passable:
		passable = accessible
		passability_changed.emit(passable)
