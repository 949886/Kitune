extends StaticBody2D
## An attackable practice target; a real host reports its own attributed kills.
signal defeated(attacker: Node)
var dead := false


func _ready() -> void:
	set_meta("device", self)


func receive_hit(_interaction: int, attacker: Node = null, _direction := 1.0) -> bool:
	if dead:
		return false
	dead = true
	set_deferred("collision_layer", 0)
	queue_redraw()
	defeated.emit(attacker)
	return true


func reset() -> void:
	dead = false
	set_deferred("collision_layer", 2)
	queue_redraw()


func _draw() -> void:
	var color := Color("ed916a") if not dead else Color("53616a")
	draw_rect(Rect2(-12, -32, 24, 32) if not dead else Rect2(-17, -8, 34, 8), color)
	if not dead:
		draw_line(Vector2(-6, -25), Vector2(6, -13), Color("713d3a"), 3)
		draw_line(Vector2(6, -25), Vector2(-6, -13), Color("713d3a"), 3)
