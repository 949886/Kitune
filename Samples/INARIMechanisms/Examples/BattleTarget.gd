extends Node2D
## Example host enemy: real hitbox and HP, deliberately independent of INARI's
## AI/player classes. The encounter receives death only after a physical hit.
signal defeated(actor: Node2D)
signal damaged(actor: Node2D, health_ratio: float)
@export var max_health := 2
@export var body_color := Color("d58e61")
var health := 2
var active := false
var peaceful := false
var dead := false
var body: StaticBody2D


func _ready() -> void:
	health = max_health
	body = StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("device", self)
	add_child(body)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(22, 36)
	shape.shape = rectangle
	shape.position.y = -18
	body.add_child(shape)


func set_active(value: bool) -> void:
	active = value and not dead
	visible = active
	body.set_deferred("collision_layer", 2 if active else 0)
	queue_redraw()


func set_peaceful(value: bool) -> void:
	peaceful = value
	queue_redraw()


func receive_hit(interaction: int, _actor: Node, _direction: float) -> void:
	if dead or not active or (interaction & 12) == 0:
		return
	health -= 2 if (interaction & 8) != 0 else 1
	# Source SpawnManager observes post-hit health before the same hit's death.
	damaged.emit(self, maxf(0.0, float(health) / max_health))
	if health <= 0:
		dead = true
		set_active(false)
		defeated.emit(self)
	queue_redraw()


func _draw() -> void:
	var tint := Color("86c5d4") if peaceful else body_color
	draw_rect(Rect2(-11, -36, 22, 36), tint)
	draw_rect(Rect2(-7, -28, 14, 5), Color("252f38"))
	draw_line(Vector2(-10, -43), Vector2(-10 + 20.0 * health / max_health, -43), Color("c5df92"), 3)
