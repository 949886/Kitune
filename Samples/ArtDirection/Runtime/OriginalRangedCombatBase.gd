extends RefCounted
## Shared source ranged-enemy sensing, path traversal, retreat and leash states.

signal state_changed(value: String)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const Retreat = preload("res://Samples/ArtDirection/Runtime/OriginalRangedRetreat.gd")
const DoorAction = preload("res://Samples/ArtDirection/Runtime/OriginalRangedDoor.gd")

var actor: CharacterBody2D
var target: CharacterBody2D:
	set(value):
		if target != value and not settings.is_empty():
			reset()
		target = value
var settings: Dictionary
var attack: Dictionary
var retreat := Retreat.new()
var door_action := DoorAction.new()
var state := "idle"
var elapsed := 0.0
var acquired := false
var route: Array[Vector2i] = []
var route_index := 0
var leash_point := Vector2.ZERO
var chase_preparing := false
var chase_preparation_time := 0.0
var retargetable := true
var retarget_pending := false


func step(delta: float) -> float:
	if settings.is_empty() or not is_instance_valid(target):
		return actor.patrol.step(delta)
	if target.dead:
		if state != "idle":
			reset()
		return 0.0
	elapsed += delta
	if not door_action.phase.is_empty():
		door_action.step(delta)
		return 0.0
	if retarget_pending:
		retarget_pending = false
		_enter_retreat("retarget")
		return 0.0
	match state:
		"idle":
			var alerted := int(actor.data.character_type) == 2 and (acquired or _in_sight())
			if alerted:
				if _clear_sight():
					if _in_attack_range():
						acquired = true
						_enter_ready()
					elif _inside_leash(target.position.x):
						acquired = true
						_enter_route("chase", target.position)
				if (
					state == "idle"
					and not _at_leash_point()
					and elapsed > float(actor.data.profile.LeashWaitTime)
				):
					_enter_leash_ready()
			if state == "idle" and not acquired:
				return actor.patrol.step(delta)
		"chase":
			if chase_preparing:
				chase_preparation_time += delta
				if chase_preparation_time <= actor.motion_duration:
					return 0.0
				chase_preparing = false
				actor.play_combat_motion("Chase")
			if _inside_leash(_ground_point().x) and _in_attack_range() and _clear_sight():
				_enter_ready()
			else:
				return _walk_route(float(actor.data.profile.f_ChaseSpeed))
		"retreat", "retarget":
			return _walk_route(float(actor.data.profile.RunAwaySpeed))
		"leash_ready":
			if _animation_finished():
				_enter_route("leash_back", leash_point)
		"leash_back":
			# Returning clears the source combat target, but its sight checks remain
			# active. Attack range is checked before the chase boundary, as in Unity.
			if _in_sight() and _clear_sight():
				if _in_attack_range():
					acquired = true
					_enter_ready()
				elif _inside_leash(_ground_point().x, false):
					acquired = true
					_enter_route("chase", target.position)
			if state == "leash_back":
				return _walk_route(float(actor.data.profile.f_PatrolSpeed))
	return 0.0


func reset() -> void:
	if settings.is_empty():
		return
	door_action.reset()
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	acquired = false
	chase_preparing = false
	retarget_pending = false
	route.clear()
	_change("idle")
	if not actor.dead:
		actor.play_motion("Idle")


func _enter_ready() -> void:
	assert(false, "Concrete ranged enemy must select its own attack sequence")


func request_retarget() -> void:
	retarget_pending = true


func _enter_retreat(value := "retreat") -> void:
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	_enter_route(value, retreat.destination(), false)


func _enter_leash_ready() -> void:
	acquired = false
	actor.motion_animation.set_process(true)
	actor.ranged_presentation.set_aiming(false)
	_change("leash_ready")
	actor.play_combat_motion("RunReady")


func _change(value: String) -> void:
	# AttackState.Exit resets this flag, including interrupted attacks. Merely
	# leaving Ready, resetting a target or finishing Retarget does not reset it.
	if state == "shot" and value != state:
		retargetable = true
	if state in ["chase", "retreat", "retarget", "leash_back"] and value != state:
		route.clear()
		route_index = 0
	if value != "chase":
		chase_preparing = false
	state = value
	elapsed = 0.0
	state_changed.emit(state)


func _ground_point() -> Vector2:
	return actor.patrol.navigation.world_center(
		actor.patrol.navigation.nearest(actor.patrol._feet())
	)


func _at_leash_point() -> bool:
	return (
		absf(_ground_point().x - leash_point.x)
		< float(settings.arrival_distance) * actor.PIXELS_PER_UNIT
	)


func _enter_route(value: String, destination: Vector2, clamp_leash := true) -> void:
	_change(value)
	actor.ranged_presentation.set_aiming(false)
	_set_route(destination, clamp_leash)
	actor.play_combat_motion("MoveX" if value == "leash_back" else "Chase")


func _set_route(destination: Vector2, clamp_leash := true) -> void:
	var navigation: RefCounted = actor.patrol.navigation
	destination = navigation.world_center(navigation.nearest(destination))
	var leash: float = float(actor.data.profile.LeashRange) * actor.PIXELS_PER_UNIT
	if clamp_leash and leash > 0.0:
		destination.x = clampf(destination.x, leash_point.x - leash, leash_point.x + leash)
	route = navigation.path(
		navigation.nearest(actor.patrol._feet()), navigation.nearest(destination)
	)
	route_index = 0


func _walk_route(speed: float) -> float:
	var current: Vector2i = actor.patrol.navigation.nearest(actor.patrol._feet())
	if (
		route_index < route.size()
		and (
			route[route_index].x == current.x
			or absf(actor.get_position_delta().x) <= actor.patrol.SKIN
		)
	):
		route_index += 1
	if route_index >= route.size():
		if state == "chase":
			_chase_arrived()
			return 0.0
		# EnemyRetargetPattern yields the complete RunAway coroutine first.
		# That queues Idle; its later AttackReady request loses the first-wins
		# LateChangeState guard. The next Idle update can acquire the player.
		_change("idle")
		actor.patrol.initialized = false
		actor.play_motion("Idle")
		return 0.0
	var direction := 1.0 if route[route_index].x >= current.x else -1.0
	_on_route_move()
	actor.facing = direction
	if door_action.try_begin():
		return 0.0
	return direction * speed * actor.PIXELS_PER_UNIT if actor.patrol._can_move(direction) else 0.0


func _on_route_move() -> void:
	pass


func _chase_arrived() -> void:
	# The source recomputes only after reaching the existing route endpoint.
	# A nearby occluded target leaves the enemy waiting in Chase, rather than
	# restarting Idle and its return timer every frame.
	var feet := _ground_point()
	if not _inside_leash(feet.x):
		_change("idle")
		actor.play_motion("Idle")
		return
	var navigation: RefCounted = actor.patrol.navigation
	var destination: Vector2 = navigation.world_center(navigation.nearest(target.position))
	var threshold := _chase_distance()
	if absf(destination.x - feet.x) > threshold:
		_set_route(destination)
	if route_index >= route.size():
		actor.play_motion("Idle")
	elif actor.motion != "Chase:0":
		chase_preparing = true
		chase_preparation_time = 0.0
		actor.play_combat_motion("RunReady")


func _chase_distance() -> float:
	return (
		float(actor.data.profile.AttackRange.x)
		* float(settings.chase_path_fraction)
		* actor.PIXELS_PER_UNIT
	)


func _animation_finished() -> bool:
	# StateMachine.CheckAnimationEnd compares its elapsed clock to the Animator
	# state length. A looping angle clip still ends the combat state after one
	# cycle; waiting for every sprite track to stop would trap upward shots.
	return actor.motion_duration > 0.0 and elapsed > actor.motion_duration


func _animation_frame() -> int:
	if actor.motion_animation.tracks.is_empty():
		return 0
	var track: Dictionary = actor.motion_animation.tracks[0]
	return floori(float(track.time) * float(track.clip.frame_rate))


func _center() -> Vector2:
	return actor.global_position + actor.body_shape.position


func _target_center() -> Vector2:
	return target.global_position + target.body_shape.position


func _in_sight() -> bool:
	for entry in [["v2_SightRange", 1.0], ["v2_BackSightRange", -1.0]]:
		var range: Dictionary = actor.data.profile[entry[0]]
		var size: Vector2 = Vector2(range.x, range.y) * actor.PIXELS_PER_UNIT
		if _overlap_box(_center() + Vector2(actor.facing * size.x * 0.5 * entry[1], 0), size):
			return true
	return false


func _in_attack_range() -> bool:
	var range: Dictionary = actor.data.profile.AttackRange
	return _overlap_box(_center(), Vector2(range.x, range.y) * actor.PIXELS_PER_UNIT)


func _overlap_box(center: Vector2, size: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = size
	return _overlap(shape, center)


func _too_close() -> bool:
	var shape := CircleShape2D.new()
	shape.radius = float(actor.data.profile.RangeCloseDistance) * actor.PIXELS_PER_UNIT
	return _overlap(shape, _center())


func _overlap(shape: Shape2D, center: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = Collision.PLAYER
	return actor.get_world_2d().direct_space_state.intersect_shape(query).any(
		func(hit: Dictionary): return hit.collider == target
	)


func _clear_sight() -> bool:
	return _ray(_center(), _target_center(), Collision.SIGHT_SURFACE).is_empty()


func _inside_leash(x: float, unlimited := true) -> bool:
	var leash: float = float(actor.data.profile.LeashRange) * actor.PIXELS_PER_UNIT
	return (unlimited and leash <= 0.0) or absf(x - leash_point.x) < leash


func _ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	return actor.get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(from, to, mask)
	)
