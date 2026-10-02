extends Area2D
## InteractiveSaveTrigger's guarded first entry. The demo keeps this state for
## the current level run; restarting a level intentionally creates a fresh run.
## The source's addStamina/animator fields are unused by TrySave: do not invent
## healing, stamina rewards or an interaction-button requirement here.

signal saved(checkpoint: Area2D)

const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")

var source: Dictionary
var activated := false
var player: WeakRef
## A copied device supplies eligibility and handles saved through a signal.
## The original demo supplies its one player explicitly, without preloading it.
var accept_actor: Callable


func configure(record: Dictionary, actor: Node2D = null) -> void:
	source = record
	player = weakref(actor) if is_instance_valid(actor) else null
	transform = Assets.matrix(record.transform)
	collision_layer = 0
	collision_mask = Collision.PLAYER
	monitorable = false
	var box := RectangleShape2D.new()
	box.size = Assets.vec(record.size)
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = Assets.vec(record.offset)
	add_child(shape)
	body_entered.connect(enter)


func enter(actor: Node2D) -> void:
	if activated:
		return
	if accept_actor.is_valid():
		if not accept_actor.call(actor):
			return
		activated = true
		saved.emit(self)
		return
	if player == null or player.get_ref() != actor or actor.dead:
		return
	# Source Trigger.OnEnter and OnPlayerEnter both call TrySave; its canSave
	# guard means one notification, even when both callbacks run in one frame.
	activated = true
	var offset: Dictionary = actor.tuning.body_offset
	var unity_origin_offset := Vector2(
		-float(offset.x) * actor.units, -actor.body_size.y / 2.0 + float(offset.y) * actor.units
	)
	actor.checkpoint = Assets.vec(source.spawn_origin) - unity_origin_offset
	actor.checkpoint_facing = float(source.facing)
	actor.checkpoint_source = str(source.id)
	saved.emit(self)
