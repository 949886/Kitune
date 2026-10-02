extends StaticBody2D
## PlatformController's waypoint clock and easing. Gameplay motion is explicit:
## visual children retain their original projection/sort parents; a passenger is
## moved once with collision checks, without adding platform speed to a jump.

signal started
signal arrived
signal passenger_crushed(actor: CharacterBody2D)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var source: Dictionary
var waypoints: Array[Vector2] = []
var from_index := 0
var progress := 0.0
var clock := 0.0
var next_move := 0.0
var stopped := true
var moving := false
var arrival_count := 0
var source_time_scale := 1.0
var player: CharacterBody2D
var visuals: Array[Node2D] = []
var bounds := Rect2()
var wheels: Array[Node2D] = []
var lights: Array[Node2D] = []
var light_tweens: Array[Tween] = []
## Optional host integration. The original demo supplies its own actor contract;
## reusable scenes supply a shape and grip flags without requiring that script.
var passenger_shape: CollisionShape2D
var passenger_climbing := false
var passenger_hanging := false
var use_passenger_adapter := false


func configure(record: Dictionary, actor: CharacterBody2D, source_visuals: Array) -> void:
	source = record
	player = actor
	transform = Assets.matrix(record.transform)
	for point: Array in record.waypoints:
		# Native waypoints add world translation only, not the platform basis.
		waypoints.append(position + Assets.vec(point))
	assert(waypoints.size() >= 2)
	stopped = bool(source.fields.IsStopped)
	collision_layer = (
		Collision.SOLID
		| Collision.PROJECTILE_SURFACE
		| Collision.RAY_SURFACE
		| Collision.SIGHT_SURFACE
		| Collision.STATIC_SURFACE
		| Collision.STUCK_SURFACE
	)
	collision_mask = Collision.PLAYER
	set_meta("source_go", source.go)
	set_meta("source_layer", "Ground")
	set_meta("climbable", true)
	var first := true
	for path: Array in record.paths:
		var polygon := CollisionPolygon2D.new()
		var points := PackedVector2Array()
		for item: Array in path:
			var point := Assets.vec(item)
			points.append(point)
			bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
			first = false
		polygon.polygon = points
		add_child(polygon)
	# JSON numbers are floats. Normalize IDs once; Array.has deliberately
	# distinguishes integer and float Variants even when their values match.
	var child_ids: Array = record.children.map(func(value): return int(value))
	var wheel_ids: Array = record.wheels.map(func(value): return int(value))
	var light_ids: Array = record.lights.map(func(value): return int(value))
	for visual: Node2D in source_visuals:
		if int(visual.data.get("go", visual.data.get("tilemap_go", -1))) in child_ids:
			visuals.append(visual)
		if int(visual.data.get("go", -1)) in wheel_ids:
			wheels.append(visual)
		if int(visual.data.get("go", -1)) in light_ids:
			lights.append(visual)
	# Unity updates platforms in LateUpdate after the player's regular movement.
	process_physics_priority = 100


func on_source_time_scale(value: float) -> void:
	source_time_scale = value


func activate() -> void:
	if not stopped:
		# The shipped two-stop platforms reverse in flight with continuous easing.
		from_index += 1
		progress = 1.0 - progress
		return
	next_move = clock + float(source.fields.WaitTime)
	stopped = false
	_set_lights(true)
	started.emit()


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	clock += delta
	moving = false
	if stopped or clock < next_move or source_time_scale <= 0.0:
		return
	if source.fields.Cyclic:
		from_index %= waypoints.size()
	var destination := (from_index + 1) % waypoints.size()
	var length := waypoints[from_index].distance_to(waypoints[destination])
	assert(length > 0.0, "Source platform has coincident waypoints")
	progress = minf(
		1.0, progress + source_time_scale * delta * float(source.fields.Speed) * 16.0 / length
	)
	var power := float(source.fields.EaseAmount) + 1.0
	var a := pow(progress, power)
	var eased := a / (a + pow(1.0 - progress, power))
	var target := waypoints[from_index].lerp(waypoints[destination], eased)
	var motion := target - position
	moving = not motion.is_zero_approx()
	_carry((get_parent() as Node2D).global_transform.basis_xform(motion))
	position = target
	for visual: Node2D in visuals:
		visual.position += motion
	for wheel: Node2D in wheels:
		# Unity Mathf.Sign(0) is +1, so a vertical platform also turns its gears.
		var direction := -1.0 if motion.x < 0.0 else 1.0
		wheel.rotation -= deg_to_rad(
			direction * motion.length() / 16.0 / float(source.fields.radius)
		)
	if progress >= 1.0:
		progress = 0.0
		from_index += 1
		if not source.fields.Cyclic and from_index >= waypoints.size() - 1:
			from_index = 0
			waypoints.reverse()
		stopped = bool(source.fields.IsStopped)
		next_move = clock + float(source.fields.WaitTime)
		_set_lights(false)
		arrival_count += 1
		arrived.emit()


func _set_lights(enabled: bool) -> void:
	for tween: Tween in light_tweens:
		tween.kill()
	light_tweens.clear()
	for light: Node2D in lights:
		var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(
			light, "modulate:a", 1.0 if enabled else 0.0, float(source.fields.WaitTime)
		)
		light_tweens.append(tween)


func _carry(motion: Vector2) -> void:
	if (
		motion.is_zero_approx()
		or not is_instance_valid(player)
		or (not use_passenger_adapter and player.dead)
		or not player.can_process()
	):
		return
	var surface := global_transform * bounds
	var shape: CollisionShape2D = passenger_shape if use_passenger_adapter else player.body_shape
	if not is_instance_valid(shape) or shape.disabled or shape.shape == null:
		return
	var body: Rect2 = shape.global_transform * shape.shape.get_rect()
	var skin: float = player.safe_margin
	var overlap_x := (
		body.end.x > surface.position.x + skin and body.position.x < surface.end.x - skin
	)
	var overlap_y := (
		body.end.y > surface.position.y + skin and body.position.y < surface.end.y - skin
	)
	var top := overlap_x and absf(body.end.y - surface.position.y) <= skin * 2.0
	var under := overlap_x and absf(body.position.y - surface.end.y) <= skin * 2.0
	var side := (
		overlap_y
		and (
			minf(absf(body.end.x - surface.position.x), absf(body.position.x - surface.end.x))
			<= skin * 2.0
		)
	)
	var carried := Vector2.ZERO
	var crush_axis := Vector2.ZERO
	if top and player.velocity.y >= 0.0:
		carried = motion
		if motion.y < 0.0:
			crush_axis = Vector2.UP
	elif side and (passenger_climbing if use_passenger_adapter else player.climbing):
		carried = motion
		crush_axis = Vector2(signf(motion.x), 0.0)
	elif under and (passenger_hanging if use_passenger_adapter else player.ceiling_hang):
		carried = motion
		if motion.y > 0.0:
			crush_axis = Vector2.DOWN
	else:
		# Push actors reached during this step, including a thin moving surface.
		if overlap_y and motion.x > 0.0 and body.position.x >= surface.end.x - skin:
			carried.x = maxf(0.0, surface.end.x + motion.x - body.position.x + skin)
		elif overlap_y and motion.x < 0.0 and body.end.x <= surface.position.x + skin:
			carried.x = minf(0.0, surface.position.x + motion.x - body.end.x - skin)
		if overlap_x and motion.y < 0.0 and body.end.y <= surface.position.y + skin:
			carried.y = minf(0.0, surface.position.y + motion.y - body.end.y - skin)
		elif overlap_x and motion.y > 0.0 and body.position.y >= surface.end.y - skin:
			carried.y = maxf(0.0, surface.end.y + motion.y - body.position.y + skin)
		crush_axis = carried.sign()
	if carried.is_zero_approx():
		return
	# Ignore only the carrier for this explicit move; world walls still block.
	player.add_collision_exception_with(self)
	var contact := player.move_and_collide(carried)
	player.remove_collision_exception_with(self)
	if contact != null and contact.get_remainder().dot(crush_axis) > skin:
		passenger_crushed.emit(player)
		if not use_passenger_adapter:
			player.die(true)
