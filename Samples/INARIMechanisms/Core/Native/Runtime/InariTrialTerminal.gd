extends Area2D
## A source TimeAttackTrigger or TimeAttackTriggerDest proximity/input endpoint.
const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")
const Animator = preload("InariMechanismAnimator.gd")
var source: Dictionary
var manager: Node
var player: Node
var animation := Animator.new()
var available := true
var prompt := ""
signal proximity_changed(actor: Node, nearby: bool)
var use_host_adapter := false
var accept_actor: Callable
var request_use: Callable
var actor_layers := 4
var outlines: Array[ShaderMaterial] = []


func configure(record: Dictionary, trial: Node) -> void:
	source = record
	manager = trial
	player = trial.player
	prompt = "F / Y  启动计时挑战" if record.kind == "TimeAttackTrigger" else "F / Y  停止计时，打开奖励门"
	transform = Assets.matrix(record.trigger.transform)
	collision_layer = 0
	collision_mask = actor_layers if use_host_adapter else Collision.PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(record.trigger.size)
	shape.shape = rectangle
	shape.position = Assets.vec(record.trigger.offset)
	add_child(shape)
	add_child(animation)
	animation.configure(record.animation, trial.stage)
	for outline: Dictionary in record.outlines:
		var visual: Node = trial.stage.visuals_by_go[outline.go]
		visual.material = visual.material.duplicate()
		var surface: ShaderMaterial = visual.material
		surface.set_shader_parameter("base_outline_enabled", true)
		surface.set_shader_parameter("base_outline_color", Assets.color(outline.color))
		for key in ["alpha", "glow", "width", "pixel_perfect", "pixel_width"]:
			surface.set_shader_parameter("base_outline_" + key, outline[key])
		outlines.append(surface)
	body_entered.connect(_enter)
	body_exited.connect(_exit)


func _enter(body: Node) -> void:
	if use_host_adapter:
		if available and accept_actor.call(body):
			proximity_changed.emit(body, true)
			_fade_outline(1.0)
		return
	if body == player and available:
		player.interaction_target = self
		_fade_outline(1.0)


func _exit(body: Node) -> void:
	if use_host_adapter:
		proximity_changed.emit(body, false)
		_fade_outline(0.0)
		return
	if body == player and player.interaction_target == self:
		player.interaction_target = null
	if body == player:
		_fade_outline(0.0)


func _fade_outline(value: float) -> void:
	# Native OnEnter/OnExit starts an OutQuad tween without killing old ones.
	for surface: ShaderMaterial in outlines:
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_method(
			func(alpha: float): surface.set_shader_parameter("base_outline_alpha", alpha),
			float(surface.get_shader_parameter("base_outline_alpha")),
			value,
			float(source.fields.alphaTime)
		)


func interact(actor: Node) -> bool:
	if use_host_adapter:
		if not available or not accept_actor.call(actor) or not _touching_actor(actor):
			return false
		return request_use.is_valid() and bool(request_use.call(actor))
	if actor != player or not available or not has_overlapping_bodies():
		return false
	return manager.use(self)


func _touching_actor(actor: Node) -> bool:
	if overlaps_body(actor):
		return true
	# A stationary body whose layer was changed can be missing from Godot's
	# cached Area2D overlap list until it moves. Confirm current shape contact
	# in the physics space before rejecting an explicitly requested interaction.
	var shape: CollisionShape2D = get_child(0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = collision_mask
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 64):
		if hit.collider == actor:
			return true
	return false


func disable() -> void:
	available = false
	_exit(player)
	set_deferred("monitoring", false)


func play(state_name: String) -> void:
	for index in source.animation.states.size():
		if source.animation.states[index].name == state_name:
			animation.play(index)
