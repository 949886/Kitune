extends Node2D
## Self-contained visual preview, no host player or project input map required.
@onready var device: Node2D = $Device
@onready var label: Label = $Label
var inspecting := false

func _process(_delta: float) -> void:
	label.text = "DisappearingPlatform3D\nSpace: activate | R: reset | V: inspect thickness\nState: %s | Timer: %.2f" % [["READY", "COUNTDOWN", "HIDDEN"][device.state], device.elapsed]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_SPACE:
		device.activate()
	elif event.physical_keycode == KEY_R:
		device.reset()
	elif event.physical_keycode == KEY_V:
		inspecting = not inspecting
		device.set_inspection_angle(35.0 if inspecting else 0.0)
