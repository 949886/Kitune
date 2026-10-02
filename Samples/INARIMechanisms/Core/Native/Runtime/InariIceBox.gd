extends StaticBody2D
## ElectroBox's one-shot charge and flood fill. A stuck kunai only anchors;
## ObjectShurikenComponent requests damage when its teleport info is consumed.

signal discharged(affected: Array)

const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")
const Animator = preload("InariMechanismAnimator.gd")

var source: Dictionary
var rules: Dictionary
var stage: Node
var player: Node
var animator := Animator.new()
var consumed := false
var fired := false
var affected: Array[Node] = []
var visited: Dictionary = {}
var charge_clock := 0.0
var blink_deadline := 0.0
var blink := 1.0
var loop_started := false
var surface: ShaderMaterial
var outline := 0.0
var grid: Transform2D
var cell_size := 0.0
## Portable hosts supply explicit observer/target callbacks. The original demo
## keeps its native player/enemy path, sharing charging and flood-fill rules.
var use_host_adapter := false
var observer_position: Callable
var freeze_candidates: Callable
var apply_freeze: Callable
var blocking_mask := Collision.SOLID | Collision.SIGHT_SURFACE | Collision.INTERACTIVE_WALL
var ground_mask := Collision.SIGHT_SURFACE


func configure(record: Dictionary, owner_stage: Node, actor: Node, settings: Dictionary) -> void:
	source = record
	rules = settings
	stage = owner_stage
	player = actor
	transform = Assets.matrix(source.collider.transform)
	grid = Assets.matrix(source.grid_transform)
	cell_size = float(source.cell_size)
	collision_layer = Collision.DAMAGEABLE | Collision.PROJECTILE_SURFACE
	collision_mask = 0
	set_meta("source_layer", "InteractiveObject")
	set_meta("climbable", bool(source.fields.ShurikenComponent.canShurikenHit))
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(source.collider.size)
	shape.shape = rectangle
	shape.position = Assets.vec(source.collider.offset)
	add_child(shape)
	var visual: Node = stage.visuals_by_go[source.renderer_go]
	visual.material = visual.material.duplicate()
	surface = visual.material
	outline = float(source.outline.alpha)
	surface.set_shader_parameter("base_outline_enabled", true)
	surface.set_shader_parameter("base_outline_color", Assets.color(source.outline.color))
	for key in ["alpha", "glow", "width", "pixel_perfect", "pixel_width"]:
		surface.set_shader_parameter("base_outline_" + key, source.outline[key])
	add_child(animator)
	animator.configure(source.animation, stage)


func receive_study_hit(hit: Dictionary, _direction: float) -> bool:
	# ElectroBox overrides AcceptHealthChange without the parent's attack mask.
	# Its dead event has no listener, so the spent machine remains an anchor.
	if consumed:
		return true
	consumed = true
	stage.audio.stop_events(self)
	stage.audio.play_event("ice_start", self)
	var actor: Node = hit.get("source_actor")
	if is_instance_valid(actor) and actor.has_signal("camera_shake_requested"):
		actor.camera_shake_requested.emit("Attack")
	_advance_blink()
	return true


func study_kunai_destination(actor: Node, point: Vector2) -> Vector2:
	var direction: Vector2 = (point - actor.body_shape.global_position).normalized()
	if source.fields.ShurikenComponent.canOffsetTeleportPos:
		point += direction * float(actor.combat.WeakPointAttackInfo.Offset[0]) * actor.units
	receive_study_hit({"interaction": 64, "source_actor": actor}, direction.x)
	return point


func _physics_process(delta: float) -> void:
	var native_origin := Vector2.INF
	if use_host_adapter:
		if observer_position.is_valid():
			native_origin = observer_position.call()
	elif is_instance_valid(player):
		native_origin = (
			player.position
			+ Vector2(
				-float(player.tuning.body_offset.x) * player.units,
				-player.body_size.y / 2.0 + float(player.tuning.body_offset.y) * player.units
			)
		)
	var distance := (
		_source_distance(global_position, native_origin) if native_origin.is_finite() else INF
	)
	if not loop_started and not consumed and distance < float(rules.loop_distance) * cell_size:
		loop_started = true
		stage.audio.play_event("ice_loop", self)
	var target := 0.0
	if (
		not consumed
		and distance <= float(source.fields.range) * cell_size
		and not _ground_between(native_origin)
	):
		target = 1.0
	# Native Update kills/restarts this tween every frame, rather than finishing
	# one full-duration tween after entering the radius.
	var t := clampf(delta / float(source.fields.alphaTime), 0.0, 1.0)
	outline = lerpf(outline, target, 0.5 - cos(t * PI) * 0.5)
	surface.set_shader_parameter("base_outline_alpha", outline)
	if consumed and not fired:
		charge_clock += delta
		if charge_clock >= blink_deadline:
			if blink_deadline >= float(source.fields.waitingTime):
				_discharge()
			else:
				_advance_blink()


func _advance_blink() -> void:
	var interval := lerpf(
		float(source.fields.blinkIntervalMax),
		float(source.fields.blinkIntervalMin),
		blink_deadline / float(source.fields.waitingTime)
	)
	blink_deadline += interval
	blink = 1.0 - blink
	surface.set_shader_parameter("hit_blend", blink)


func _ground_between(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point, ground_mask)
	# Outline queries only Ground; skip other source layers along the ray.
	while true:
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		if use_host_adapter or hit.collider.get_meta("source_layer", "") == "Ground":
			return true
		query.exclude = query.exclude + [hit.rid]
	return false


func _world_grid() -> Transform2D:
	return stage.global_transform * grid if use_host_adapter else grid


func _source_distance(a: Vector2, b: Vector2) -> float:
	return (
		stage.to_local(a).distance_to(stage.to_local(b)) if use_host_adapter else a.distance_to(b)
	)


func cell_at(point: Vector2) -> Vector2i:
	var local := _world_grid().affine_inverse() * point / cell_size
	# Unity floors Y before reflection, including negative coordinates.
	return Vector2i(floori(local.x), floori(-local.y))


func cell_center(cell: Vector2i) -> Vector2:
	return _world_grid() * ((Vector2(cell.x, -cell.y) + Assets.vec(source.anchor)) * cell_size)


func flood() -> Dictionary:
	var start := cell_at(global_position)
	var queue: Array[Vector2i] = [start]
	var cells := {start: true}
	var index := 0
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2.ONE * float(rules.flood_box_size) * cell_size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rectangle
	query.collision_mask = blocking_mask
	query.exclude = [get_rid()]
	while index < queue.size():
		var cell := queue[index]
		index += 1
		# Unity's BoxCast is aligned to source world XY, independently of the
		# tilemap basis. Only a portable host transforms that source space.
		var frame: Transform2D = (
			stage.global_transform if use_host_adapter else Transform2D.IDENTITY
		)
		query.transform = Transform2D(frame.x, frame.y, cell_center(cell))
		var blocked := false
		for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 10):
			if (
				use_host_adapter
				or hit.collider.get_meta("source_layer", "") in rules.blocking_layers
			):
				blocked = true
				break
		if blocked:
			continue
		# Preserve the native visit-before-radius-test order: blocked cells and
		# the one-cell outer boundary are still eligible to contain an enemy.
		for step: Vector2i in [Vector2i.UP * -1, Vector2i.RIGHT, Vector2i.DOWN * -1, Vector2i.LEFT]:
			var neighbor := cell + step
			if cells.has(neighbor):
				continue
			cells[neighbor] = true
			if (
				_source_distance(global_position, cell_center(neighbor))
				< float(source.fields.range) * cell_size
			):
				queue.append(neighbor)
	return cells


func _discharge() -> void:
	fired = true
	surface.set_shader_parameter("hit_blend", 0.0)
	visited = flood()
	var candidates: Array = freeze_candidates.call() if use_host_adapter else stage.enemies
	for enemy: Node in candidates:
		if use_host_adapter:
			if is_instance_valid(enemy) and visited.has(cell_at(enemy.global_position)):
				if apply_freeze.call(enemy, float(source.fields.stunTime)):
					affected.append(enemy)
			continue
		if (
			enemy.source_active()
			and not enemy.dead
			and enemy.data.kunai.canShurikenHit
			and visited.has(cell_at(enemy.global_position))
		):
			if enemy.stun(float(source.fields.stunTime)):
				affected.append(enemy)
	stage.spawn_effect("Eff_Freezing", global_position, 0.0)
	for index in source.animation.states.size():
		if source.animation.states[index].name == "aircon_boom":
			animator.play(index)
	discharged.emit(affected)
