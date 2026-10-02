extends "WorkshopPlayer.gd"
@onready var range_state: Node = $ShurikenRange
var projectile: Node2D


func _unhandled_key_input(event: InputEvent) -> void:
	super._unhandled_key_input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		projectile.launch(self, range_state, Vector2(0, -16), Vector2(facing, 0))
