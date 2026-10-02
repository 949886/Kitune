extends "WorkshopPlayer.gd"
## Preview locks host input only. Physics still supports the actor on the floor.
var input_enabled := true


func set_input_enabled(value: bool) -> void:
	input_enabled = value
	left = false
	right = false
	pending_jump = false
	pending_attack = false
	velocity = Vector2.ZERO


func _unhandled_key_input(event: InputEvent) -> void:
	if input_enabled:
		super._unhandled_key_input(event)
