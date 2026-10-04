extends CharacterBody2D
## Workshop movement kept local: no project InputMap or INARI Core dependency.
@export var speed := 260.0
@export var gravity := 1000.0
@export var jump_speed := 440.0
var left := false
var right := false
var facing := 1.0
var pending_jump := false
var pending_attack := false
var attack_remaining := 0.0


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
		KEY_J, KEY_K:
			pending_attack = event.pressed


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
	pending_attack = false
	if position.y > 650:
		position = Vector2(140, 400)
		velocity = Vector2.ZERO
	queue_redraw()


func clear_input() -> void:
	left = false
	right = false
	pending_jump = false
	pending_attack = false
	attack_remaining = 0.0
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		clear_input()


func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("9dd9e5")
	style.set_corner_radius_all(5)
	draw_style_box(style, Rect2(-9, -32, 18, 32))
	draw_circle(Vector2(facing * 4, -25), 2, Color("172d3f"))
	if attack_remaining > 0:
		draw_arc(Vector2(facing * 23, -20), 24, -1.4, 1.4, 16, Color("ffe3a1"), 3)
