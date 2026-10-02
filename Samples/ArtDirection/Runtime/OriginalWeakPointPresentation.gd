extends RefCounted
## Source stack branches and the independently scaled weak-point range holder.

signal range_changed(contact: bool)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Outline = preload("res://Samples/ArtDirection/Runtime/OriginalEnemyOutline.gd")

var actor: Node
var data: Dictionary
var active_stacks: Array[bool] = []
var range_active := false
var range_scale := 1.0
var scale_duration := 0.1
var scale_tweens: Array[Dictionary] = []
var contact_in_range := false
var outline := Outline.new()


func configure(owner_node: Node) -> void:
	actor = owner_node
	var source: Dictionary = Assets.read_json(Assets.ROOT + "weakpoints.json")
	data = (
		actor.data.weakpoint_binding
		if actor.data.has("weakpoint_binding")
		else source.actors[str(int(actor.data.go))]
	)
	outline.configure(actor, data.outline_visuals, source.outline)
	range_changed.connect(outline.range_changed)
	scale_duration = float(source.scale_duration)
	active_stacks.resize(data.stacks.size())
	active_stacks.fill(false)
	apply_visibility()


func hit(stack: int) -> void:
	if data.is_empty() or stack <= 0:
		return
	var index := stack - 1
	active_stacks[index] = true
	range_active = true
	# DOScale does not kill earlier tweens on the same target. Preserve their
	# insertion order and the scale visible when each new tween was created.
	var destination := float(actor.data.profile.WeakPointRangeScale[index])
	scale_tweens.append({"from": range_scale, "to": destination, "elapsed": 0.0})
	apply_visibility()


func reset() -> void:
	active_stacks.fill(false)
	range_active = false
	# The original controller hides its objects without restoring localScale
	# or cancelling DOScale. Re-enabling begins from the retained scale.
	apply_visibility()


func step(delta: float) -> void:
	outline.step(delta)
	for tween: Dictionary in scale_tweens:
		tween.elapsed = minf(float(tween.elapsed) + delta, scale_duration)
		var progress := float(tween.elapsed) / scale_duration
		# The installed DOTween.dll defaults to Ease.OutQuad.
		var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
		range_scale = lerpf(float(tween.from), float(tween.to), eased)
	scale_tweens = scale_tweens.filter(
		func(tween: Dictionary): return tween.elapsed < scale_duration
	)
	var contact := _contact()
	if contact != contact_in_range:
		contact_in_range = contact
		range_changed.emit(contact)


func pose_for(go: Variant, pose: Transform2D) -> Transform2D:
	if go not in data.get("range_members", []):
		return pose
	var center := Assets.matrix(data.range_transform).origin
	pose.origin = center + (pose.origin - center) * range_scale
	pose.x *= range_scale
	pose.y *= range_scale
	return pose


func apply_visibility() -> void:
	if data.is_empty():
		return
	for index in active_stacks.size():
		for go in data.stacks[index]:
			actor.visuals[go].visible = active_stacks[index] and not actor.dead
	for go in data.range_members:
		actor.visuals[go].visible = range_active and not actor.dead


func _contact() -> bool:
	if not range_active or actor.dead or not actor.is_inside_tree():
		return false
	var pose := Assets.matrix(data.range_transform)
	var collider: Dictionary = data.range_collider
	var offset: Vector2 = Vector2(collider.m_Offset.x, -collider.m_Offset.y) * actor.PIXELS_PER_UNIT
	var shape := CircleShape2D.new()
	shape.radius = (
		float(collider.m_Radius)
		* actor.PIXELS_PER_UNIT
		* maxf(pose.x.length(), pose.y.length())
		* range_scale
	)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = pose * (offset * range_scale) + actor.position - actor.origin
	query.collision_mask = Collision.PLAYER
	return not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
