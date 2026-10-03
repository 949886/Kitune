@tool
extends Node2D
## Independent 3D relief device projected into a host 2D world.
## Self-contained copy boundary; original DisappearingPlatform is untouched.
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
const Mechanism = preload("MechanicalModel.gd")
var mechanism: Node3D
var _fold_start := 1.75
var _fold_end := 1.95
var _recover_pose_end := 0.2
var viewport: SubViewport
var camera: Camera3D
var display: Sprite2D
var model: Node3D
var _actor: WeakRef
var _alive := Callable()
var _animation_index := 0
var _animation_time := 0.0
var _recover_blend := 0.0
var _pending_active := false

# Inspection owns no extra nodes and never changes the model or 2D collision.
# Each instance retains its own gameplay camera snapshot and orbit coordinates.
const ORBIT_SENSITIVITY := 0.008
const ORBIT_PITCH_LIMIT := deg_to_rad(80.0)
const ORBIT_MIN_ZOOM := 0.15
const ORBIT_MAX_ZOOM := 4.0
var _inspecting := false
var _orbit_saved: Dictionary = {}
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_zoom := 1.0
var _orbit_drag_button := MOUSE_BUTTON_NONE


func _ready() -> void:
	# Relative to this script, so renaming/nesting the copied folder is safe.
	var folder: String = get_script().resource_path.get_base_dir() + "/Assets/"
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	assert(document.records.has(settings.source_key), "Unknown source platform preset")
	record = document.records[settings.source_key]
	_library = document.sprites
	_build_projection()
	mechanism = Mechanism.new()
	mechanism.name = "MechanicalAssembly"
	# Authored backplate contour uses PNG-space anchor (82, 42). Preserve
	# each original preset's subpixel artwork offset without moving physics.
	for item: Dictionary in record.visuals:
		if item.sprite == "sharedassets2_2519":
			var offset: Array = _library[item.sprite].offset
			mechanism.position = Vector3(float(item.transform[4]) + float(offset[0]) + 82.0, -(float(item.transform[5]) + float(offset[1])) - 42.0, 0.0)
			break
	model.add_child(mechanism)
	mechanism.setup()
	visuals[record.states[0].track.go] = mechanism
	visuals[record.states[0].alpha.go] = mechanism.alarm
	_configure_hinge_timing()
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
	exit_inspection()
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
	mechanism.current_key = str(key) if key != null else ""
	mechanism.set_fold(_fold_fraction(index, time))
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


## Read the source fold interval rather than allowing the imported animation
## duration to change gameplay timing. The Blender action defines the motion.
func _configure_hinge_timing() -> void:
	var active: Array = record.states[1].track.frames
	var ready_key: String = record.states[0].track.frames[0][1]
	var hidden_key: String = record.states[2].track.frames[0][1]
	for frame: Array in active:
		if frame[1] != ready_key:
			break
		_fold_start = float(frame[0])
	for frame: Array in active:
		if frame[1] == hidden_key:
			_fold_end = float(frame[0])
			break
	for frame: Array in record.states[3].track.frames:
		if frame[1] == ready_key:
			_recover_pose_end = float(frame[0])
			break


func _fold_fraction(index: int, time: float) -> float:
	match index:
		1:
			return clampf(inverse_lerp(_fold_start, _fold_end, time), 0.0, 1.0)
		2:
			return 1.0
		3:
			# Hold the outgoing pose through the source blend, then unfold
			# continuously to the same source end time (no angle discontinuity).
			var start := _recover_blend * float(record.states[3].track.speed)
			return 1.0 - clampf(inverse_lerp(minf(start, _recover_pose_end - 0.000001), _recover_pose_end, time), 0.0, 1.0)
	return 0.0


func _build_projection() -> void:
	# Bounds include EVERY pose and halo, rather than only the ready pose.
	var bounds := Rect2()
	var first := true
	for item: Dictionary in record.visuals:
		var pose: Array = item.transform
		var transform_2d := Transform2D(Vector2(pose[0],pose[1]), Vector2(pose[2],pose[3]), Vector2(pose[4],pose[5]))
		var keys: Array = [item.sprite]
		if item.go == record.states[0].track.go:
			for state_record: Dictionary in record.states:
				for frame: Array in state_record.track.frames:
					if frame[1] != null and not keys.has(frame[1]):
						keys.append(frame[1])
		for key: String in keys:
			var entry: Dictionary = _library[key]
			var factor := 16.0 / float(entry.ppu)
			var rect := Rect2(Vector2(entry.offset[0],entry.offset[1])*factor, Vector2(entry.size[0],entry.size[1])*factor)
			var transformed := transform_2d * rect
			bounds = transformed if first else bounds.merge(transformed)
			first = false
	bounds = Rect2(bounds.position.floor() - Vector2(2,2), bounds.end.ceil() - bounds.position.floor() + Vector2(4,4))
	viewport = SubViewport.new()
	viewport.name = "Projection3D"
	viewport.size = Vector2i(bounds.size)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	model = Node3D.new()
	model.name = "SolidGeometry"
	viewport.add_child(model)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = bounds.size.y
	camera.position = Vector3(bounds.get_center().x, -bounds.get_center().y, 500.0)
	camera.near = 0.05
	camera.far = 1000.0
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.74, 0.8)
	environment.ambient_light_energy = 0.8
	camera.environment = environment
	viewport.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.name = "MechanicalKeyLight"
	key_light.rotation_degrees = Vector3(-25, -30, 0)
	key_light.light_energy = 1.1
	key_light.shadow_enabled = false
	viewport.add_child(key_light)
	display = Sprite2D.new()
	display.name = "Projected3D"
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	display.position = bounds.position
	display.centered = false
	add_child(display)


## Free visual inspection around the device origin, not the oversized halo's
## image bounds. The host chooses when to enter and routes its input here before
## its gameplay controller. Calling enter twice never overwrites the snapshot.
func enter_inspection() -> void:
	if _inspecting or not is_instance_valid(camera):
		return
	_orbit_saved = {
		"transform": camera.transform,
		"size": camera.size,
		"projection": camera.projection,
		"display_position": display.position,
		"shadow_visibility": {},
	}
	# The oversized ambient shadow is a front-view presentation layer, not part
	# of the platform's solid body. Hide it in orbit so rear views stay readable.
	for item: Dictionary in record.visuals:
		if item.sprite == "sharedassets0_446" and visuals.has(item.go):
			var shadow: MeshInstance3D = visuals[item.go]
			_orbit_saved.shadow_visibility[item.go] = shadow.visible
			shadow.visible = false
	_inspecting = true
	_orbit_drag_button = MOUSE_BUTTON_NONE
	_orbit_yaw = deg_to_rad(35.0)
	_orbit_pitch = deg_to_rad(20.0)
	_orbit_zoom = 1.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Keep the orbit target at this Node2D's origin on screen even when the halo
	# is asymmetric. This presentation-only adjustment is restored on exit.
	display.position = -Vector2(viewport.size) * 0.5
	_update_inspection_camera()


## Restore the exact snapshot, rather than reconstructing a nominal front view.
## No timer, mesh, animation, collision or actor state is changed here.
func exit_inspection() -> void:
	if not _inspecting:
		return
	_inspecting = false
	_orbit_drag_button = MOUSE_BUTTON_NONE
	if is_instance_valid(camera):
		camera.projection = _orbit_saved.projection
		camera.size = _orbit_saved.size
		camera.transform = _orbit_saved.transform
	if is_instance_valid(display):
		display.position = _orbit_saved.display_position
	for go: Variant in _orbit_saved.shadow_visibility:
		if is_instance_valid(visuals[go]):
			visuals[go].visible = _orbit_saved.shadow_visibility[go]
	_orbit_saved.clear()
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func is_inspecting() -> bool:
	return _inspecting


## Returns true for every event while inspecting so hosts can consume it before
## gameplay input. V/reset ownership stays in the host; this API is reusable.
## Any mouse button can drag. Wheel up/down zooms with hard, positive bounds.
func handle_inspection_input(event: InputEvent) -> bool:
	if not _inspecting:
		return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_orbit_drag_button = event.button_index
			elif event.button_index == _orbit_drag_button:
				_orbit_drag_button = MOUSE_BUTTON_NONE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			var steps := maxf(0.0, event.factor)
			_orbit_zoom = clampf(_orbit_zoom * pow(1.12, direction * steps), ORBIT_MIN_ZOOM, ORBIT_MAX_ZOOM)
			_update_inspection_camera()
	elif event is InputEventMouseMotion and _orbit_drag_button != MOUSE_BUTTON_NONE:
		# Ignore stale drags after a missed release (for example focus changes).
		var mask := 1 << (_orbit_drag_button - 1)
		if event.button_mask & mask == 0:
			_orbit_drag_button = MOUSE_BUTTON_NONE
		else:
			_orbit_yaw = wrapf(_orbit_yaw - event.relative.x * ORBIT_SENSITIVITY, -PI, PI)
			_orbit_pitch = clampf(_orbit_pitch + event.relative.y * ORBIT_SENSITIVITY, -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
			_update_inspection_camera()
	return true


func _update_inspection_camera() -> void:
	var radius := 500.0
	camera.position = Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch)) * radius
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.size = maxf(0.01, float(_orbit_saved.size) * _orbit_zoom)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_orbit_drag_button = MOUSE_BUTTON_NONE


func _exit_tree() -> void:
	exit_inspection()


## Backward-compatible fixed-angle helper. New hosts should use enter/exit and
## handle_inspection_input. A zero angle restores the exact gameplay snapshot.
func set_inspection_angle(degrees: float) -> void:
	if is_zero_approx(degrees):
		exit_inspection()
		return
	enter_inspection()
	_orbit_yaw = deg_to_rad(degrees)
	_orbit_pitch = 0.0
	_update_inspection_camera()
