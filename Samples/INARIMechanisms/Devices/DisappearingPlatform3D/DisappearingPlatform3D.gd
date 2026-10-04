@tool
extends Node2D
## Independent 3D mechanical device projected into a host 2D world.
## Self-contained copy boundary; original DisappearingPlatform is untouched.
signal activated
signal disappeared
signal recovered
signal state_changed(value: int)

enum State { READY, COUNTDOWN, HIDDEN }
enum AnimationState { IDLE, ACTIVE, ACTIVE_IDLE, RECOVER }
@export_group("Gameplay")
@export_range(0.0, 30.0, 0.01, "or_greater") var disappear_delay := 109.0 / 60.0
@export_range(0.0, 30.0, 0.01, "or_greater") var hidden_seconds := 1.25
@export_range(0.0, 4.0, 0.01, "or_greater") var time_scale := 1.0
@export var sound_enabled := true

@export_group("Folding")
@export_range(0.0, 30.0, 0.001, "or_greater") var fold_start := 1.75
@export_range(0.0, 30.0, 0.001, "or_greater") var fold_end := 1.9500000476837158
@export_range(0.0, 30.0, 0.001, "or_greater") var active_animation_end := 1.9895836353525738
@export_range(0.0, 30.0, 0.001, "or_greater") var recovery_hold := 0.11356039345264435
@export_range(0.0, 30.0, 0.001, "or_greater") var recovery_end := 0.20000000298023224
@export_range(0.0, 30.0, 0.001, "or_greater") var recovery_animation_end := 0.21699076692560482

@export_group("Alarm Lamp")
## Seconds from activation. The lamp starts dark and flips at every entry.
@export var lamp_toggle_times := PackedFloat32Array([
	0.21666666865348816, 0.4166666567325592, 0.6166666746139526,
	0.800000011920929, 0.9666666388511658, 1.1166666746139526,
	1.2333333492279053, 1.3333333730697632, 1.4166666269302368,
	1.4500000476837158, 1.4833333492279053, 1.5166666507720947,
	1.5499999523162842, 1.5833333730697632, 1.6166666746139526,
	1.649999976158142, 1.6833332777023315, 1.7166666984558105, 1.75,
]):
	set(value):
		lamp_toggle_times = value.duplicate()
## Normalized recovery time (0–1) to opacity (1–0), sampled without baking.
@export var recovery_alpha: Curve

var solid_layers: int:
	get:
		return solid.collision_layer if is_instance_valid(solid) else 1
	set(value):
		if is_instance_valid(solid):
			solid.collision_layer = value
@export_group("Scene Bindings")
@export_node_path("CharacterBody2D") var actor_path: NodePath

var state := State.READY
var elapsed := 0.0
var disappear_after := 0.0
var recover_after := 0.0
@export var solid: StaticBody2D
@export var shape: CollisionPolygon2D
@export var audio: AudioStreamPlayer
const Mechanism = preload("MechanicalModel.gd")
const ProjectionNode = preload("Components/Projection3D/Projection3D.gd")
@export var projection: ProjectionNode
var mechanism: Mechanism
var _configuration_ready := false
var _projection_ready := false
var _binding_projection := false
var _initialized := false
var viewport: SubViewport
var camera: Camera3D
var display: Sprite2D
var model: Node3D
var _actor: WeakRef
var _alive := Callable()
var _animation_index := AnimationState.IDLE
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


func _init() -> void:
	# Isolate script defaults as well as values assigned by a PackedScene.
	lamp_toggle_times = lamp_toggle_times.duplicate()


func _ready() -> void:
	if _initialized:
		return
	if not _configure():
		set_physics_process(false)
		return
	for required: String in ["projection", "solid", "shape", "audio"]:
		if not is_instance_valid(get(required)):
			push_error("DisappearingPlatform3D: assign the '%s' scene node reference." % required)
			set_physics_process(false)
			return
	if not projection.rebuilding.is_connected(_on_projection_rebuilding):
		projection.rebuilding.connect(_on_projection_rebuilding)
		projection.rebuilt.connect(_on_projection_rebuilt)
	_binding_projection = true
	var built := projection.ensure_built()
	_binding_projection = false
	if not built or not _bind_projection():
		set_physics_process(false)
		return
	# Editing validates the injected mechanical scene without writing palettes,
	# lamp scripts or gameplay poses into authored model resources.
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	disappear_after = disappear_delay
	recover_after = hidden_seconds
	_initialized = true
	set_physics_process(not Engine.is_editor_hint())
	_sample_animation()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	process_physics_priority = 100
	if not actor_path.is_empty():
		bind_actor(get_node_or_null(actor_path) as CharacterBody2D)


func _bind_projection() -> bool:
	viewport = projection.viewport
	camera = projection.camera
	display = projection.sprite
	model = projection.scene_container
	mechanism = projection.scene_instance as Mechanism
	_projection_ready = false
	if mechanism == null:
		push_error("DisappearingPlatform3D: Projection.scene must reference a MechanicalModel scene.")
		return false
	if not mechanism.setup():
		return false
	_projection_ready = true
	return true


func _on_projection_rebuilding() -> void:
	_projection_ready = false
	set_physics_process(false)
	viewport = null
	camera = null
	display = null
	model = null
	mechanism = null


func _on_projection_rebuilt() -> void:
	if _binding_projection or not _configuration_ready:
		return
	if not _initialized:
		_ready()
		return
	if not _bind_projection():
		return
	_sample_animation()
	if _inspecting:
		# Replacement preserves the inspection state and angles but restores the
		# replacement's configured front camera when inspection ends.
		_orbit_saved = {"transform": camera.transform, "size": camera.size,
			"projection": camera.projection, "display_position": display.position}
		mechanism.set_inspection_materials(true)
		display.position = -Vector2(viewport.size) * 0.5
		_update_inspection_camera()
	set_physics_process(not Engine.is_editor_hint())


func _configure() -> bool:
	_configuration_ready = false
	var errors := validate_configuration()
	if not errors.is_empty():
		for error: String in errors:
			push_error("DisappearingPlatform3D: " + error)
		return false
	_configuration_ready = true
	return true


func validate_configuration() -> PackedStringArray:
	var errors := PackedStringArray()
	for property: String in ["disappear_delay", "hidden_seconds", "time_scale", "fold_start", "fold_end", "active_animation_end", "recovery_hold", "recovery_end", "recovery_animation_end"]:
		var value: float = get(property)
		if not is_finite(value) or value < 0.0:
			errors.append("%s must be finite and nonnegative." % property)
	if fold_end <= fold_start:
		errors.append("fold_end must be later than fold_start.")
	if active_animation_end < fold_end:
		errors.append("active_animation_end must be at or after fold_end.")
	if recovery_end <= recovery_hold:
		errors.append("recovery_end must be later than recovery_hold.")
	if recovery_animation_end < recovery_end:
		errors.append("recovery_animation_end must be at or after recovery_end.")
	var previous := -1.0
	for time: float in lamp_toggle_times:
		if not is_finite(time) or time < 0.0 or time <= previous or time > active_animation_end:
			errors.append("lamp_toggle_times must increase strictly from zero through active_animation_end.")
			break
		previous = time
	if recovery_alpha == null or recovery_alpha.point_count < 2:
		errors.append("Assign recovery_alpha with at least two points from (0, 1) to (1, 0).")
	else:
		if not recovery_alpha.get_point_position(0).is_equal_approx(Vector2(0.0, 1.0)) or not recovery_alpha.get_point_position(recovery_alpha.point_count - 1).is_equal_approx(Vector2(1.0, 0.0)):
			errors.append("recovery_alpha must start at (0, 1) and end at (1, 0).")
		previous = -1.0
		for index in recovery_alpha.point_count:
			var point := recovery_alpha.get_point_position(index)
			if not point.is_finite() or point.x <= previous or point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0 or not is_finite(recovery_alpha.get_point_left_tangent(index)) or not is_finite(recovery_alpha.get_point_right_tangent(index)):
				errors.append("recovery_alpha needs ordered finite points in the unit square and finite tangents.")
				break
			previous = point.x
	return errors


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	warnings.append_array(validate_configuration())
	for required: String in ["projection", "solid", "shape", "audio"]:
		if not is_instance_valid(get(required)):
			warnings.append("Assign the '%s' scene node reference." % required)
	return warnings


## The optional predicate lets a host exclude dead actors without depending on
## a particular player state machine. No strong reference survives room teardown.
func bind_actor(actor: CharacterBody2D, alive := Callable()) -> void:
	_actor = weakref(actor) if actor != null else null
	_alive = alive


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _initialized or not _projection_ready:
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
	if not _initialized or not _projection_ready or state != State.READY:
		return false
	elapsed = 0.0
	state = State.COUNTDOWN
	if _animation_index == AnimationState.RECOVER:
		# Keep a new activation pending until the recovery animation finishes.
		_pending_active = true
	else:
		_play_animation(AnimationState.ACTIVE)
	if sound_enabled:
		audio.play()
	activated.emit()
	state_changed.emit(state)
	return true


## Physics and animation share one clock; SceneTree pause stops both. Advancing
## explicitly is useful for deterministic verification without real-time sleeps.
func advance(delta: float) -> void:
	if not _initialized or not _projection_ready:
		return
	var step := maxf(0.0, delta) * time_scale
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
			_recover_blend = recovery_hold
			_play_animation(AnimationState.RECOVER)
			recovered.emit()
			state_changed.emit(state)


func reset() -> void:
	if not _initialized:
		return
	exit_inspection()
	state = State.READY
	elapsed = 0.0
	_pending_active = false
	_recover_blend = 0.0
	shape.set_deferred("disabled", false)
	audio.stop()
	_play_animation(AnimationState.IDLE)
	state_changed.emit(state)


func _play_animation(index: int) -> void:
	_animation_index = index
	_animation_time = 0.0
	_sample_animation()


func _advance_animation(delta: float) -> void:
	_animation_time += delta
	match _animation_index:
		AnimationState.ACTIVE:
			if _animation_time >= active_animation_end:
				_play_animation(AnimationState.ACTIVE_IDLE)
		AnimationState.RECOVER:
			if _animation_time >= recovery_animation_end:
				var next := AnimationState.ACTIVE if _pending_active else AnimationState.IDLE
				_pending_active = false
				_play_animation(next)
	_sample_animation()


func _sample_animation() -> void:
	if not _projection_ready or Engine.is_editor_hint():
		return
	mechanism.set_fold(_fold_fraction(_animation_index, _animation_time))
	var alpha := _lamp_alpha(_animation_index, _animation_time)
	if _animation_index == AnimationState.RECOVER and _recover_blend > 0.0 and _animation_time < _recover_blend:
		alpha = lerpf(1.0, alpha, _animation_time / _recover_blend)
	mechanism.alarm.modulate.a = clampf(alpha, 0.0, 1.0)


## The lamp starts dark and flips at each authored countdown flash time.
## Recovery is a normalized editable Curve, independent of model geometry.
func _lamp_alpha(index: int, time: float) -> float:
	match index:
		AnimationState.ACTIVE:
			var on := false
			for toggle: float in lamp_toggle_times:
				if toggle > time + 0.000001:
					break
				on = not on
			return 1.0 if on else 0.0
		AnimationState.ACTIVE_IDLE:
			return 1.0
		AnimationState.RECOVER:
			if time + 0.000001 >= recovery_end:
				return 0.0
			return recovery_alpha.sample(clampf(time / recovery_end, 0.0, 1.0))
	return 0.0


func _fold_fraction(index: int, time: float) -> float:
	match index:
		AnimationState.ACTIVE:
			return clampf(inverse_lerp(fold_start, fold_end, time), 0.0, 1.0)
		AnimationState.ACTIVE_IDLE:
			return 1.0
		AnimationState.RECOVER:
			# Hold the outgoing pose through the blend, then unfold continuously.
			return 1.0 - clampf(inverse_lerp(_recover_blend, recovery_end, time), 0.0, 1.0)
	return 0.0


## Free visual inspection around the device origin, not the oversized halo's
## image bounds. The host chooses when to enter and routes its input here before
## its gameplay controller. Calling enter twice never overwrites the snapshot.
func enter_inspection() -> void:
	if not _initialized or not _projection_ready or _inspecting or not is_instance_valid(camera):
		return
	_orbit_saved = {
		"transform": camera.transform,
		"size": camera.size,
		"projection": camera.projection,
		"display_position": display.position,
	}
	_inspecting = true
	mechanism.set_inspection_materials(true)
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
	if is_instance_valid(mechanism):
		mechanism.set_inspection_materials(false)
	_orbit_drag_button = MOUSE_BUTTON_NONE
	if is_instance_valid(camera):
		camera.projection = _orbit_saved.projection
		camera.size = _orbit_saved.size
		camera.transform = _orbit_saved.transform
	if is_instance_valid(display):
		display.position = _orbit_saved.display_position
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
	if not _projection_ready:
		return true
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
