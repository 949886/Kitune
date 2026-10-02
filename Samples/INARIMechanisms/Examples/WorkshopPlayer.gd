extends CharacterBody2D
## Small example controller, deliberately unrelated to the Rossi player.
## Raw key events keep the copied example independent of project InputMap.
const DRAW_ORDER_GROUP := &"workshop_actors"
const ParticleEmitter = preload("../Core/Native/Runtime/OriginalParticleEmitter.gd")
@export var speed := 180.0
@export var gravity := 1000.0
@export var jump_speed := 350.0
var left := false
var right := false
var facing := 1.0
var attack_remaining := 0.0
var pending_attack := false
var attack_interaction := 4
var pending_jump := false
var _draw_order_refresh_pending := false


func _enter_tree() -> void:
	# All controller variants inherit this hook, including WindRunner, which
	# defines its own _ready. Keep other sample actors out of the device scan
	# so two actors cannot repeatedly raise one another's drawing order.
	add_to_group(DRAW_ORDER_GROUP)
	get_parent().child_entered_tree.connect(_scene_child_entered)
	_queue_draw_order_refresh()


func _exit_tree() -> void:
	get_parent().child_entered_tree.disconnect(_scene_child_entered)


func _scene_child_entered(node: Node) -> void:
	if node is CanvasItem and not node.is_in_group(DRAW_ORDER_GROUP):
		_queue_draw_order_refresh()


func _queue_draw_order_refresh() -> void:
	if _draw_order_refresh_pending:
		return
	_draw_order_refresh_pending = true
	# Devices create their visual children in _ready. Defer the scan until
	# both the scene and its devices are complete; the same path handles a
	# newly installed portal room or a rebuilt time-trial attempt.
	_refresh_draw_order.call_deferred()


func _refresh_draw_order() -> void:
	_draw_order_refresh_pending = false
	if not is_inside_tree():
		return
	var parent_z := 0
	if z_as_relative and not top_level:
		parent_z = _effective_draw_z(get_parent() as CanvasItem)
	var foreground_z := _highest_scene_z(get_parent(), parent_z) + 1
	z_index = clampi(
		foreground_z - parent_z, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX
	)


func _highest_scene_z(node: Node, highest: int) -> int:
	# UI and transition covers have their own canvas. Preserve their layering
	# and the devices' internal source order instead of using a fixed Z band.
	if node is CanvasLayer or node.is_in_group(DRAW_ORDER_GROUP):
		return highest
	if node is CanvasItem:
		if node.get_canvas() != get_canvas():
			return highest
		highest = maxi(highest, _effective_draw_z(node))
	if node is ParticleEmitter and node.effect != null:
		# Ambient sprites may not exist yet. Their absolute Z comes from the
		# configured renderer, so include it before the first emission too.
		var renderer: Dictionary = node.data.renderer
		highest = maxi(highest, node.effect.sorting.call([
			renderer.m_SortingLayer, renderer.m_SortingOrder
		]))
	for child: Node in node.get_children():
		highest = _highest_scene_z(child, highest)
	return highest


func _effective_draw_z(item: CanvasItem) -> int:
	var order := 0
	while item != null:
		order += item.z_index
		if not item.z_as_relative or item.top_level:
			break
		item = item.get_parent() as CanvasItem
	return order


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or event.echo:
		return
	match event.physical_keycode:
		KEY_A, KEY_LEFT:
			left = event.pressed
		KEY_D, KEY_RIGHT:
			right = event.pressed
		KEY_SPACE:
			pending_jump = event.pressed
		KEY_J:
			pending_attack = event.pressed
			attack_interaction = 4
		KEY_K:
			pending_attack = event.pressed
			attack_interaction = 8


func _physics_process(delta: float) -> void:
	var axis := float(right) - float(left)
	if axis != 0:
		facing = axis
	velocity.x = axis * speed
	velocity.y += gravity * delta
	if pending_jump and is_on_floor():
		velocity.y = -jump_speed
	pending_jump = false
	move_and_slide()
	attack_remaining = maxf(0.0, attack_remaining - delta)
	if pending_attack and attack_remaining == 0.0:
		attack_remaining = 0.2
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 24.0
		query.shape = shape
		query.transform.origin = global_position + Vector2(facing * 23, -20)
		query.collision_mask = 2
		for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
			var device: Node = hit.collider.get_meta("device", null)
			if device != null:
				device.receive_hit(attack_interaction, self, facing)
	pending_attack = false
	if position.y > 650:
		position = Vector2(140, 400)
		velocity = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	draw_style_box(_body_style(), Rect2(-9, -32, 18, 32))
	draw_circle(Vector2(facing * 4, -25), 2, Color("172d3f"))
	if attack_remaining > 0:
		draw_arc(Vector2(facing * 23, -20), 24, -1.4, 1.4, 16, Color("ffe3a1"), 3)


func _body_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("9dd9e5")
	style.set_corner_radius_all(5)
	return style
