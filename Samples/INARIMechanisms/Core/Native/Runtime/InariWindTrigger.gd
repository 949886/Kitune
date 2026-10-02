extends Area2D
## MoveSpeedChangeTrigger: one stamina award, deferred spawn activation and global cooldown.

const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")

signal activated(player: Node)
signal began
signal cooled
signal cancelled
signal healing_requested(player: Node, amount: int)
signal stamina_requested(player: Node, amount: float)
signal stamina_feedback_requested(player: Node)

var source: Dictionary
var stamina_once := false
var clock := 0.0
var cooldown_until := 0.0
var pending_player: WeakRef
var story_heal := 0
var cooling := false
var audio: Node
var bound_player: WeakRef
## Host callbacks replace player-specific fields without loading its controller.
var use_host_adapter := false
var accept_actor: Callable
var is_spawning: Callable
var apply_buff: Callable
var can_finish_cooldown: Callable


func configure(data: Dictionary, heal_amount: int, player: Node = null) -> void:
	source = data
	bound_player = weakref(player) if is_instance_valid(player) else null
	story_heal = heal_amount
	transform = Assets.matrix(data.transform)
	collision_layer = 0
	collision_mask = Collision.PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(data.size)
	shape.shape = rectangle
	shape.position = Assets.vec(data.offset)
	add_child(shape)
	body_entered.connect(enter)


func enter(player: Node) -> void:
	if use_host_adapter:
		if not accept_actor.call(player):
			return
		healing_requested.emit(player, story_heal)
		if not stamina_once:
			stamina_feedback_requested.emit(player)
			stamina_requested.emit(player, float(source.stamina))
			stamina_once = true
	else:
		if bound_player == null or bound_player.get_ref() != player:
			return
		if player.story_mode:
			player.damage.health = mini(player.damage.maximum, player.damage.health + story_heal)
			player.health_changed.emit(player.damage.health, player.damage.maximum)
		if not stamina_once:
			player.stamina_feedback.trigger(player.wind_buff.level, player.wind_buff.previous_level)
			player.restore_stamina(float(source.stamina))
			stamina_once = true
	if pending_player != null or cooling or clock < cooldown_until:
		return
	# The original Animator starts before the coroutine waits for the spawn action.
	began.emit()
	if _spawning(player):
		pending_player = weakref(player)
	else:
		_activate(player)
	# BuffStart borrows the sound immediately after starting the deferred coroutine.
	if is_instance_valid(audio):
		audio.play_event("wind_buff_trigger", self)


func _activate(player: Node) -> void:
	if use_host_adapter:
		apply_buff.call(player)
	else:
		player.wind_buff.request(maxi(1, player.wind_buff.level))
	cooldown_until = clock + float(source.cooldown)
	cooling = true
	pending_player = null
	activated.emit(player)


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	clock += delta
	if (
		cooling
		and clock >= cooldown_until
		and (not can_finish_cooldown.is_valid() or can_finish_cooldown.call())
	):
		cooling = false
		cooled.emit()
	if pending_player == null:
		return
	var player: Node = pending_player.get_ref()
	if not is_instance_valid(player):
		cancel_pending()
	elif use_host_adapter and not accept_actor.call(player):
		cancel_pending()
	elif not _spawning(player):
		_activate(player)


func _spawning(player: Node) -> bool:
	return bool(is_spawning.call(player)) if use_host_adapter else player.action_state == "spawn"


func cancel_pending() -> void:
	if pending_player != null:
		pending_player = null
		cancelled.emit()
