extends Node2D
## RepeatingMonsterSpawner's entity lifecycle, with explicit host factories.
## The host owns AI, damage and persistence. A factory receives a world point
## and returns {actor: Node2D, idle: Callable(), tint: Callable(Color)} after
## adding the new actor to its scene. BowMan's separate GFX renderer is handled
## by its tint callback; this coordinator never assumes a renderer hierarchy.
signal flags_requested(actor: Node2D, repeated: bool, loaded: bool)
signal member_registered(key: StringName, actor: Node2D)
signal member_unregistered(key: StringName, actor: Node2D)
signal persistence_remove_requested(actor: Node2D)
signal replacement_failed(key: StringName)
const Configuration = preload("RepeatSettings.gd")
@export var settings: Configuration = preload("RepeatSettings.tres")
var factories: Dictionary = {}
var bindings: Dictionary = {}
var waiting: Array[Dictionary] = []
var fading: Array[Dictionary] = []
var created: Array[WeakRef] = []
var active := true
var realtime := 0.0
var last_tick := 0


func _ready() -> void:
	last_tick = Time.get_ticks_usec()


func register_factory(kind: StringName, factory: Callable) -> void:
	assert(factory.is_valid())
	factories[kind] = factory


## Register authored initial enemies before they can die. Their source Start
## marks flags but does not add them to the global list a second time or fade.
func bind_enemy(key: StringName, actor: Node2D, idle: Callable, tint: Callable) -> Dictionary:
	assert(settings.kinds.has(String(key)) and not bindings.has(key))
	assert(is_instance_valid(actor) and idle.is_valid() and tint.is_valid())
	var binding := {"actor": weakref(actor), "idle": idle, "tint": tint}
	bindings[key] = binding
	flags_requested.emit(actor, true, false)
	return binding


func notify_defeated(key: StringName, actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not bindings.has(key) or bindings[key].actor.get_ref() != actor:
		return false
	# Remove the logical death subscription before host callbacks can reenter.
	# Duplicate/stale deaths cannot respawn the same generation twice.
	bindings.erase(key)
	member_unregistered.emit(key, actor)
	persistence_remove_requested.emit(actor)
	# Disabling a GameObject does not remove external UnityEvent listeners:
	# death still unregisters the entity, but cannot start a new coroutine.
	if active:
		waiting.append({"key": key, "deadline": -1.0, "duration": settings.wait_seconds})
	return true


func _process(delta: float) -> void:
	var tick := Time.get_ticks_usec()
	var real_delta := delta / Engine.time_scale if Engine.time_scale > 0 else (tick - last_tick) / 1000000.0
	last_tick = tick
	advance(real_delta, delta)


## Public deterministic clock entry point, also used by the runtime process.
## Newly-created fades execute once immediately, as the source coroutine does.
func advance(real_delta: float, scaled_delta: float) -> void:
	if not active:
		return
	realtime += maxf(real_delta, 0.0)
	for fade: Dictionary in fading.duplicate():
		if not _fade_step(fade, scaled_delta):
			fading.erase(fade)
	for pending: Dictionary in waiting.duplicate():
		if not active or not waiting.has(pending):
			break
		if float(pending.deadline) < 0:
			pending.deadline = realtime + float(pending.duration)
		if realtime < float(pending.deadline):
			continue
		waiting.erase(pending)
		_replace(pending.key, scaled_delta)


func _replace(key: StringName, scaled_delta: float) -> void:
	var kind := StringName(settings.kinds[String(key)])
	if not factories.has(kind) or not factories[kind].is_valid():
		replacement_failed.emit(key)
		return
	var result: Dictionary = factories[kind].call(to_global(settings.placements[String(key)]))
	var actor: Node2D = result.get("actor")
	if not is_instance_valid(actor) or not result.get("idle", Callable()).is_valid() or not result.get("tint", Callable()).is_valid():
		replacement_failed.emit(key)
		return
	created.append(weakref(actor))
	var binding := bind_enemy(key, actor, result.idle, result.tint)
	member_registered.emit(key, actor)
	# Retain this generation even if a registration callback immediately kills
	# it. The old coroutine must never fade a future replacement for the key.
	var fade := binding.duplicate()
	fade.elapsed = 0.0
	fade.tint.call(Color(1, 1, 1, 0))
	if _fade_step(fade, scaled_delta):
		fading.append(fade)


func _fade_step(fade: Dictionary, scaled_delta: float) -> bool:
	if not is_instance_valid(fade.actor.get_ref()) or not fade.idle.is_valid() or not fade.tint.is_valid():
		return false
	if float(fade.elapsed) >= settings.fade_seconds:
		fade.tint.call(Color.WHITE)
		return false
	# Force Idle on every fade frame, including at global time_scale == 0.
	# Alpha is sampled before deltaTime is added; a zero duration skips division.
	fade.idle.call()
	fade.tint.call(Color(1, 1, 1, float(fade.elapsed) / settings.fade_seconds))
	fade.elapsed += maxf(scaled_delta, 0.0)
	return true


## Corresponds to disabling the owning Unity GameObject: cancel coroutines.
## Existing live actors keep their state and can die after reactivation.
func set_active(value: bool) -> void:
	active = value
	last_tick = Time.get_ticks_usec()
	if not value:
		waiting.clear()
		fading.clear()


## Source OnBeforeSceneChanged only destroys dynamically created enemies;
## authored initial actors belong to their scene. Pending coroutines remain
## until the owner is disabled/unloaded. The host explicitly forwards this event.
func before_scene_changed() -> void:
	for reference: WeakRef in created:
		var actor: Node = reference.get_ref()
		if is_instance_valid(actor):
			actor.queue_free()
	created.clear()


func _exit_tree() -> void:
	# Portable ownership boundary: don't leave replacements in a host sibling
	# container when this reusable device is removed without a scene transition.
	set_active(false)
	before_scene_changed()
