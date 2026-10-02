extends Node
## INARI's shipped Cinemachine framing, expressed in the study's pixel coordinates.
## The player stays on Z=0; source perspective depth is rendered by SceneProjection.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Impulse = preload("res://Samples/ArtDirection/Runtime/InariCameraImpulse.gd")
const NEGLIGIBLE_RESIDUAL := 0.01
const DAMP_EPSILON := 0.0001

@export var camera_2d: Camera2D
@export var fixed_target: Node2D
var target: Node2D
var source: Dictionary
var framing: Dictionary
var target_offset := Vector2.ZERO
var view_size := Vector2.ZERO
var freeze_remaining := 0.0
var teleport_freeze_time := 0.0
var impulse := Impulse.new()
var pixels_per_unit := 0.0
var player_origin_offset := Vector2.ZERO
var target_depth := 0.0
var camera_distance := 0.0
var guide_size := Vector2.ZERO


func configure_2d(_profile: Dictionary, player: Node2D, source_camera: Dictionary) -> void:
	var units: float = player.tuning.pixels_per_unit
	var body_offset: Dictionary = player.tuning.body_offset
	var origin_offset := Vector2(-body_offset.x * units, -player.body_size.y / 2.0 + body_offset.y * units)
	configure_host(player, source_camera, units, origin_offset, player.combat.ShurikenDashCamStopTime)
	player.teleported.connect(_on_teleported)
	player.camera_shake_requested.connect(generate_impulse)


## Explicit host adapter permits reuse without a particular player controller.
## Hosts may call _on_teleported/generate_impulse from their own event signals.
func configure_host(actor: Node2D, source_camera: Dictionary, units: float, origin_offset := Vector2.ZERO, freeze_time := 0.0) -> void:
	target = actor
	source = source_camera.duplicate(true)
	framing = source.framing
	process_priority = 300
	if camera_2d == null:
		camera_2d = Camera2D.new()
		camera_2d.name = "InariOriginalCamera"
		add_child(camera_2d)

	pixels_per_unit = units
	player_origin_offset = origin_offset
	target_offset = Vector2.ZERO
	target_depth = float(source.tracked_offset.z)
	impulse.configure(source.impulses)
	if source.follow.has("fixed_position"):
		# Timeline follows an independent ShotPoint during this native excerpt.
		# Player movement must not translate the authored conversation framing.
		if fixed_target != null:
			target = fixed_target
		else:
			target = Node2D.new()
			target.name = source.follow.game_object
			add_child(target)
			target.global_position = Assets.vec(source.follow.fixed_position)
	else:
		# Unity follows the Player collider center; the study uses a foot origin.
		target_offset = player_origin_offset
	target_offset += Vector2(source.tracked_offset.x, -source.tracked_offset.y) * units
	var height := (
		2.0 * float(source.distance) * tan(deg_to_rad(source.lens.FieldOfView) / 2.0) * units
	)
	var viewport_size := get_viewport().get_visible_rect().size
	guide_size = Vector2(height * viewport_size.x / viewport_size.y, height)
	_set_camera_distance(float(source.distance) - target_depth)

	teleport_freeze_time = freeze_time
	warp_to_target()


func _process(delta: float) -> void:
	advance(delta)
	var listener := _unity(camera_2d.global_position)
	var shake := impulse.advance(delta, listener)
	# Keep follow history separate from the final impulse correction. Otherwise
	# the damper would chase its own shake and leave residual drift afterward.
	camera_2d.offset = Vector2(shake.x, -shake.y) * pixels_per_unit
	camera_2d.force_update_scroll()


func generate_impulse(kind: String) -> void:
	# The original manager is on the output camera, not at the hit enemy's feet.
	impulse.generate(kind, _unity(camera_2d.global_position + camera_2d.offset))


func _unity(value: Vector2) -> Vector2:
	return Vector2(value.x, -value.y) / pixels_per_unit


func advance(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if freeze_remaining > 0.0:
		freeze_remaining = maxf(0.0, freeze_remaining - delta)
		return
	# Cinemachine first computes XY guide bounds at the corrected target depth,
	# then damps XYZ correction. With the source's zero dead-zone depth, guides
	# span m_CameraDistance even while the camera's world Z is still converging.
	var desired_depth := float(source.distance) - target_depth
	_set_camera_distance(
		camera_distance + damp(desired_depth - camera_distance, source.damping[2], delta)
	)

	var relative := target.global_position + target_offset - camera_2d.global_position
	var dead_size := Vector2(framing.m_DeadZoneWidth, framing.m_DeadZoneHeight)
	var correction := _outside_bounds(relative, _screen_bounds(dead_size))
	correction.x = damp(correction.x, source.damping[0], delta)
	correction.y = damp(correction.y, source.damping[1], delta)

	# Cinemachine first damps toward the dead zone, then immediately enforces the
	# outer soft-zone boundary. A large jump must not leave the target off screen.
	if not framing.m_UnlimitedSoftZone:
		var soft_size := Vector2(framing.m_SoftZoneWidth, framing.m_SoftZoneHeight)
		var bias := Vector2(framing.m_BiasX, framing.m_BiasY) * (soft_size - dead_size)
		correction += _outside_bounds(relative - correction, _screen_bounds(soft_size, bias))

	camera_2d.global_position += correction
	camera_2d.force_update_scroll()


func warp_to_target() -> void:
	freeze_remaining = 0.0
	impulse.clear()
	camera_2d.offset = Vector2.ZERO
	_set_camera_distance(float(source.distance) - target_depth)
	camera_2d.global_position = (
		target.global_position + target_offset - _screen_bounds(Vector2.ZERO).get_center()
	)
	camera_2d.force_update_scroll()


func _on_teleported(_from: Vector2, _to: Vector2) -> void:
	# PlayerStateMachine.CameraStopRoutine holds the old view before resuming follow.
	freeze_remaining = teleport_freeze_time


func _screen_bounds(size: Vector2, bias := Vector2.ZERO) -> Rect2:
	# Cinemachine ScreenY is measured from the top, just like Godot's viewport Y.
	var center := (Assets.vec(source.screen_position) + bias - Vector2.ONE * 0.5) * guide_size
	var extent := size * guide_size
	return Rect2(center - extent / 2.0, extent)


func _set_camera_distance(value: float) -> void:
	assert(value > 0.0, "The authored camera must stay behind the gameplay plane")
	camera_distance = value
	view_size = guide_size * value / float(source.distance)
	camera_2d.zoom = Vector2.ONE * get_viewport().get_visible_rect().size.y / view_size.y
	camera_2d.set_meta("source_camera_distance", value)


func _outside_bounds(point: Vector2, bounds: Rect2) -> Vector2:
	return point - point.clamp(bounds.position, bounds.end)


static func damp(value: float, damping_time: float, delta: float) -> float:
	# Cinemachine.Utility.Damper: damping time leaves 1% of the initial error.
	if damping_time < DAMP_EPSILON or absf(value) < DAMP_EPSILON:
		return value
	if delta < DAMP_EPSILON:
		return 0.0
	return value * (1.0 - exp(log(NEGLIGIBLE_RESIDUAL) * delta / damping_time))
