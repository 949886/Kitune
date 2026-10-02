extends "BattleTarget.gd"
## Training host for the factory contract; not the original BombMan AI.
var repeated := false
var loaded := true
var idle_calls := 0


func force_idle() -> void:
	idle_calls += 1
	set_peaceful(true)


func apply_tint(color: Color) -> void:
	modulate = color
	if color == Color.WHITE:
		set_peaceful(false)
