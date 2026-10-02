extends Area2D
## MonsterSpawnerTrigger + Trigger entry semantics. No player is captured by
## the delayed Spawn coroutine: leaving, loading or losing the actor afterward
## does not cancel it. Deactivating the owning GameObject cancels all waits.
signal entered(actor: Node2D)
signal exited(actor: Node2D)
signal spawn_requested
signal activation_changed(activated: bool)
signal save_requested(record: Dictionary)
const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")
var accept_actor: Callable
var is_loading: Callable
var actor_ref: WeakRef
var once := false
var spawn_term := 0.0
var activated := false
var object_active := true
var collider_enabled := true
var waits: Array[Dictionary] = []
var realtime := 0.0
var last_tick_usec := 0
var firing := false


func configure(record: Dictionary, actor: Node2D = null, on_field := false) -> void:
	actor_ref = weakref(actor) if is_instance_valid(actor) else null
	once = bool(record.fields.once)
	spawn_term = float(record.fields.spawnTerm)
	collider_enabled = bool(record.trigger.get("enabled", true))
	transform = Assets.matrix(record.trigger.transform)
	collision_layer = 0
	collision_mask = Collision.PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(record.trigger.size)
	shape.shape = rectangle
	shape.position = Assets.vec(record.trigger.offset)
	add_child(shape)
	body_entered.connect(_enter)
	body_exited.connect(_exit)
	last_tick_usec = Time.get_ticks_usec()
	# Source Start disables the whole object for an already-on-field manager.
	set_object_active(not on_field and bool(record.get("active", true)))


func _accept(body: Node2D) -> bool:
	if is_loading.is_valid() and bool(is_loading.call()):
		return false
	if accept_actor.is_valid():
		return bool(accept_actor.call(body))
	return actor_ref != null and actor_ref.get_ref() == body


func _enter(body: Node2D) -> void:
	if not object_active or not collider_enabled or not _accept(body):
		return
	if once:
		collider_enabled = false
		set_deferred("monitoring", false)
	entered.emit(body)
	if not activated and object_active:
		# Each Enter starts a coroutine. Keep its own sampled delay: shortening
		# spawnTerm between entries can make a later coroutine finish first.
		waits.append({"duration": spawn_term, "deadline": -1.0})


func _exit(body: Node2D) -> void:
	# Source Physics2D.callbacksOnDisable is true. Keep the exit notification
	# produced by disabling monitoring, including Trigger.once consumption.
	if _accept(body):
		exited.emit(body)


func _process(delta: float) -> void:
	var tick := Time.get_ticks_usec()
	var real_delta := delta / Engine.time_scale if Engine.time_scale > 0 else (tick - last_tick_usec) / 1000000.0
	last_tick_usec = tick
	advance_realtime(real_delta)


func advance_realtime(delta: float) -> void:
	if not object_active or firing:
		return
	realtime += maxf(delta, 0.0)
	for waiting: Dictionary in waits:
		# WaitForSecondsRealtime initializes its deadline on its first poll,
		# not when the yield instruction is constructed in OnPlayerEnter.
		if float(waiting.deadline) < 0.0:
			waiting.deadline = realtime + float(waiting.duration)
		if realtime < float(waiting.deadline):
			continue
		firing = true
		# Source calls StartSpawn before changing isActivated/deactivating itself.
		spawn_requested.emit()
		activated = true
		set_object_active(false)
		activation_changed.emit(true)
		firing = false
		break


func set_object_active(value: bool) -> void:
	object_active = value
	last_tick_usec = Time.get_ticks_usec()
	if not value:
		waits.clear()
	set_deferred("monitoring", value and collider_enabled)


## Trigger.ActivateTrigger enables its collider and asks for a partial save;
## it neither clears MonsterSpawnerTrigger.isActivated nor wakes an inactive
## GameObject. Hosts explicitly use set_object_active for scene activation.
func activate_trigger() -> void:
	collider_enabled = true
	set_deferred("monitoring", object_active)
	save_requested.emit(snapshot())


func restore(record: Dictionary) -> void:
	# The derived LoadData does not call Trigger.LoadData or disable a collider.
	# It also does not stop a coroutine that was already waiting.
	if record.has("isActivated"):
		activated = bool(record.isActivated)


func snapshot() -> Dictionary:
	# Source SaveData always returns the flag, even without a dirty transition.
	return {"isActivated": activated}
