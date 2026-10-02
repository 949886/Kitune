extends StaticBody2D
## InteractableTrigger: native attack flags, reusable/one-shot state and explicit
## observer targets. Animation uses the source OFF->ON / On->OFF clip tracks.

signal activated

const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")
const SceneAnimator = preload("OriginalSceneAnimation.gd")

var source: Dictionary
var consumed := false
var switched_on := false
var targets: Array[Node] = []
var animation := SceneAnimator.new()
var visuals: Dictionary
var stage: Node


func configure(record: Dictionary, owner_stage: Node, platforms: Dictionary) -> void:
	source = record
	stage = owner_stage
	visuals = stage.visuals_by_go
	transform = Assets.matrix(record.transform)
	collision_layer = Collision.DAMAGEABLE | Collision.PROJECTILE_SURFACE
	collision_mask = 0
	set_meta("climbable", bool(record.fields.ShurikenComponent.canShurikenHit))
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(record.size)
	shape.shape = rectangle
	shape.position = Assets.vec(record.offset)
	add_child(shape)
	for key: String in record.targets:
		assert(platforms.has(key), "Unresolved native platform observer")
		targets.append(platforms[key])
	stage.animation.release_visuals(record.children)
	add_child(animation)
	_play(record.default_state)


func receive_study_hit(hit: Dictionary, _direction: float) -> bool:
	if consumed or bool(source.fields.IsInvincible):
		return false
	if (int(hit.get("interaction", 0)) & int(source.fields.InteractableType)) == 0:
		return false
	if source.fields.isOnce:
		consumed = true
		set_deferred("collision_layer", 0)
	_play("On->OFF" if switched_on else "OFF->ON")
	switched_on = not switched_on
	stage.audio.play_event("lever", self)
	var player: Node = hit.get("source_actor")
	if is_instance_valid(player) and player.has_signal("camera_shake_requested"):
		player.camera_shake_requested.emit("Attack")
	for target: Node in targets:
		target.activate()
	activated.emit()
	return true


func _play(state: String) -> void:
	assert(source.states.has(state))
	animation.tracks.clear()
	animation.configure(source.states[state], visuals)


func study_kunai_destination(player: Node, point: Vector2) -> Vector2:
	# ObjectShurikenComponent permits anchoring without triggering this lever:
	# its shipped flags accept normal/heavy attacks, not ShurikenDash (64).
	var direction: Vector2 = (point - player.body_shape.global_position).normalized()
	if source.fields.ShurikenComponent.canOffsetTeleportPos:
		point += direction * float(player.combat.WeakPointAttackInfo.Offset[0]) * player.units
	receive_study_hit({"interaction": 64, "source_actor": player}, direction.x)
	return point
