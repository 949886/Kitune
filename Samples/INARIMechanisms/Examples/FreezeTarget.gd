extends CharacterBody2D
## Example host actor owns freeze duration and rejects refreshes while frozen.
@export var susceptible := true
@export var patrol_speed := 18.0
@export var patrol_distance := 16.0
var freeze_remaining := 0.0
var origin_x := 0.0
var direction := 1.0
var freeze_count := 0


func _ready() -> void:
	origin_x = position.x


func can_freeze() -> bool:
	return susceptible


func freeze(seconds: float) -> bool:
	if not susceptible or freeze_remaining > 0.0:
		return false
	freeze_remaining = seconds
	freeze_count += 1
	return true


func _physics_process(delta: float) -> void:
	if freeze_remaining > 0:
		freeze_remaining = maxf(0.0, freeze_remaining - delta)
	else:
		if absf(position.x - origin_x) >= patrol_distance:
			direction = -signf(position.x - origin_x)
		velocity.x = patrol_speed * direction
		velocity.y += 1000.0 * delta
		move_and_slide()
	queue_redraw()


func _draw() -> void:
	var tint := Color("e5ac74") if susceptible else Color("bda3cf")
	if freeze_remaining > 0:
		tint = Color("87ecff")
	draw_rect(Rect2(-10, -20, 20, 40), tint)
	draw_circle(Vector2(direction * 4, -12), 2, Color("1a2934"))
