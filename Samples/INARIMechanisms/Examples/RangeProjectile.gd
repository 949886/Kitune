extends Node2D
## Minimal host projectile for demonstrating the range contract. Artwork and
## collision responses are host-owned; the original actor is tested separately.
signal target_hit
signal launched(limit: float)
signal retired(reason: String)
@export_flags_2d_physics var surface_layers := 1
var actor: Node2D
var controller: Node
var flying := false
var stuck := false
var captured_bonus := 0.0
var captured_limit: float:
	get:
		return controller.limit_for(captured_bonus) if is_instance_valid(controller) else 0.0
var velocity := Vector2.ZERO
var origin_offset := Vector2.ZERO


func launch(player: Node2D, range_state: Node, offset: Vector2, direction: Vector2) -> void:
	actor = player
	controller = range_state
	origin_offset = offset
	global_position = actor.global_position + offset
	rotation = direction.angle()
	captured_bonus = controller.capture_bonus()
	velocity = direction.normalized() * controller.settings.flight_speed * controller.settings.pixels_per_unit
	flying = true
	stuck = false
	show()
	queue_redraw()
	launched.emit(captured_limit)


func _physics_process(delta: float) -> void:
	if not flying: return
	if not is_instance_valid(actor):
		_retire("actor_freed")
		return
	if controller.exceeds_limit(global_position, actor.global_position + origin_offset, captured_limit):
		_retire("range")
		return
	if stuck: return
	var end := global_position + velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, end, surface_layers)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = end
		return
	global_position = hit.position
	stuck = true
	if hit.collider.get_meta("range_target", false): target_hit.emit()
	queue_redraw()


func _retire(reason: String) -> void:
	flying = false
	hide()
	retired.emit(reason)


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(-5, -4), Vector2(-2, 0), Vector2(-5, 4)]), Color("e4f7f1"))
	draw_line(Vector2(-5, 0), Vector2(-19, 0), Color("fbc573"), 2)
