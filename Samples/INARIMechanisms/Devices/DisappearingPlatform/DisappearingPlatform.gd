@tool
extends Node2D
## One original four-connected tile group. This entire directory is the copy
## boundary: no autoload, global player, InputMap or external package is required.
signal activated
signal disappeared
signal recovered
signal state_changed(value: int)

enum State { READY, COUNTDOWN, HIDDEN }
const Configuration = preload("PlatformSettings.gd")
@export var settings: Configuration = preload("DefaultSettings.tres")
@export_flags_2d_physics var solid_layers := 1
@export_node_path("CharacterBody2D") var actor_path: NodePath

var state := State.READY
var elapsed := 0.0
var disappear_after := 0.0
var recover_after := 0.0
var solid: StaticBody2D
var shape: CollisionPolygon2D
var audio: AudioStreamPlayer
var record: Dictionary
var visuals: Dictionary = {}
var _library: Dictionary
var _textures: Dictionary = {}
var _actor: WeakRef
var _alive := Callable()
var _animation_index := 0
var _animation_time := 0.0
var _recover_blend := 0.0
var _pending_active := false


func _ready() -> void:
	# Relative to this script, so renaming/nesting the copied folder is safe.
	var folder: String = get_script().resource_path.get_base_dir() + "/Assets/"
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	assert(document.records.has(settings.source_key), "Unknown source platform preset")
	record = document.records[settings.source_key]
	_library = document.sprites
	for key: String in _library:
		_textures[key] = load(folder + _library[key].path)
	var sorted: Array = record.visuals.duplicate()
	sorted.sort_custom(func(a, b): return a.sort[0] < b.sort[0] or (a.sort[0] == b.sort[0] and a.sort[1] < b.sort[1]))
	for item: Dictionary in sorted:
		var sprite := Sprite2D.new()
		sprite.centered = false
		var pose: Array = item.transform
		sprite.transform = Transform2D(Vector2(pose[0], pose[1]), Vector2(pose[2], pose[3]), Vector2(pose[4], pose[5]))
		sprite.scale *= 16.0 / float(_library[item.sprite].ppu)
		sprite.modulate = Color(item.color[0], item.color[1], item.color[2], item.color[3])
		sprite.flip_h = item.flip[0]
		sprite.flip_v = item.flip[1]
		sprite.visible = item.visible
		add_child(sprite)
		visuals[item.go] = sprite
		_set_sprite(sprite, item.sprite)
	var active: Dictionary = record.states[1].track
	disappear_after = settings.disappear_delay if settings.disappear_delay >= 0.0 else float(record.fields.targetFrame) / float(active.frame_rate) / float(active.speed)
	recover_after = settings.hidden_seconds if settings.hidden_seconds >= 0.0 else float(record.fields.appearTerm)
	_sample_animation()
	if Engine.is_editor_hint():
		return
	solid = StaticBody2D.new()
	solid.collision_layer = solid_layers
	solid.collision_mask = 0
	shape = CollisionPolygon2D.new()
	var points := PackedVector2Array()
	for point: Array in record.polygon:
		points.append(Vector2(point[0], point[1]))
	shape.polygon = points
	solid.add_child(shape)
	add_child(solid)
	audio = AudioStreamPlayer.new()
	audio.stream = load(folder + document.audio.groups.activate[0])
	add_child(audio)
	# Read the actor's CURRENT slide contacts after its movement has finished.
	process_physics_priority = 100
	if not actor_path.is_empty():
		bind_actor(get_node(actor_path))


## The optional predicate lets a host exclude dead actors without depending on
## a particular player state machine. No strong reference survives room teardown.
func bind_actor(actor: CharacterBody2D, alive := Callable()) -> void:
	_actor = weakref(actor) if actor != null else null
	_alive = alive


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	advance(delta)
	var actor: CharacterBody2D = _actor.get_ref() if _actor != null else null
	if actor == null or not actor.is_on_floor() or (_alive.is_valid() and not _alive.call()):
		return
	for index in actor.get_slide_collision_count():
		var contact := actor.get_slide_collision(index)
		if contact.get_collider() == solid and contact.get_normal().dot(-global_transform.y.normalized()) > 0.999:
			activate()
			break


## Explicit host activation is also supported (e.g. a custom physics controller).
## Repeated contacts never restart a running timer; stepping off never cancels it.
func activate() -> bool:
	if state != State.READY:
		return false
	elapsed = 0.0
	state = State.COUNTDOWN
	if _animation_index == 3:
		# Unity keeps Active pending during Recover until the transition to Idle.
		_pending_active = true
	else:
		_play_animation(1)
	if settings.sound_enabled:
		audio.play()
	activated.emit()
	state_changed.emit(state)
	return true


## Physics and animation share one clock; SceneTree pause stops both. Advancing
## explicitly is useful for deterministic verification without real-time sleeps.
func advance(delta: float) -> void:
	var step := maxf(0.0, delta) * settings.time_scale
	_advance_animation(step)
	if state == State.COUNTDOWN:
		elapsed += step
		if elapsed + 0.000001 >= disappear_after:
			elapsed = 0.0
			state = State.HIDDEN
			shape.set_deferred("disabled", true)
			disappeared.emit()
			state_changed.emit(state)
	elif state == State.HIDDEN:
		elapsed += step
		if elapsed + 0.000001 >= recover_after:
			elapsed = 0.0
			state = State.READY
			# Original tile restoration is immediate at Recover, before the visible
			# opening animation finishes. Do not delay solidity to the last frame.
			shape.set_deferred("disabled", false)
			_recover_blend = float(record.states[2].transitions[0].data.m_TransitionDuration)
			_play_animation(3)
			recovered.emit()
			state_changed.emit(state)


func reset() -> void:
	state = State.READY
	elapsed = 0.0
	_pending_active = false
	_recover_blend = 0.0
	shape.set_deferred("disabled", false)
	audio.stop()
	_play_animation(0)
	state_changed.emit(state)


func _play_animation(index: int) -> void:
	_animation_index = index
	_animation_time = 0.0
	_sample_animation()


func _advance_animation(delta: float) -> void:
	_animation_time += delta
	if _animation_index in [1, 3]:
		var entry: Dictionary = record.states[_animation_index]
		var transition: Dictionary = entry.transitions[0].data
		var end: float = float(entry.track.length) / float(entry.track.speed) * float(transition.m_ExitTime) + float(transition.m_TransitionDuration)
		if _animation_time >= end:
			var next: int = int(transition.m_DestinationState)
			if next == 0 and _pending_active:
				next = 1
				_pending_active = false
			_play_animation(next)
	_sample_animation()


func _sample_animation() -> void:
	var index := _animation_index
	# Sprite object curves retain the outgoing pose during the Recover blend.
	if index == 3 and _animation_time < _recover_blend:
		index = 2
	var track: Dictionary = record.states[index].track
	var time: float = _animation_time * float(track.speed)
	if track.loop:
		time = fposmod(time, float(track.length))
	var key: Variant = track.frames[0][1]
	for frame: Array in track.frames:
		if float(frame[0]) > time + 0.000001:
			break
		key = frame[1]
	_set_sprite(visuals[track.go], key)
	# Emission alpha is a separate streamed curve, including increasingly fast
	# alarm flashes and the cubic fade during recovery. It is not in sprite pixels.
	var alpha: Dictionary = record.states[_animation_index].alpha
	var alpha_time: float = _animation_time * float(record.states[_animation_index].track.speed)
	var alpha_track: Dictionary = record.states[_animation_index].track
	if alpha_track.loop:
		alpha_time = fposmod(alpha_time, float(alpha_track.length))
	var value := _sample_curve(alpha.keys, alpha_time)
	if _animation_index == 3 and _recover_blend > 0 and _animation_time < _recover_blend:
		value = lerpf(1.0, value, _animation_time / _recover_blend)
	visuals[alpha.go].modulate.a = clampf(value, 0.0, 1.0)


func _sample_curve(keys: Array, time: float) -> float:
	var selected: Array = keys[0]
	for key: Array in keys:
		if float(key[0]) > time + 0.000001:
			break
		selected = key
	var t := maxf(0.0, time - float(selected[0]))
	var c: Array = selected[1]
	return ((float(c[0]) * t + float(c[1])) * t + float(c[2])) * t + float(c[3])


func _set_sprite(sprite: Sprite2D, key: Variant) -> void:
	if key == null:
		sprite.texture = null
		return
	sprite.texture = _textures[key]
	var offset: Array = _library[key].offset
	sprite.offset = Vector2(offset[0], offset[1])
