extends Node2D
## Self-contained visual preview, no host player or project input map required.
@onready var device: Node2D = $Device
@onready var label: Label = $Label
var inspecting := false


func _process(_delta: float) -> void:
	var controls := "V: return | Mouse drag: orbit | Wheel: zoom | R: reset + return" if inspecting else "Space: activate | R: reset | V: free orbit view"
	label.text = "DisappearingPlatform3D\n%s\nState: %s | Timer: %.2f" % [controls, ["READY", "COUNTDOWN", "HIDDEN"][device.state], device.elapsed]


# Handle inspection at the input stage, before any host gameplay's unhandled
# key/mouse callbacks. Even key releases and mouse attack events are consumed.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V:
			set_inspecting(not inspecting)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			set_inspecting(false)
			device.reset()
			get_viewport().set_input_as_handled()
			return
	if inspecting:
		device.handle_inspection_input(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		device.activate()
		get_viewport().set_input_as_handled()


func set_inspecting(enabled: bool) -> void:
	inspecting = enabled
	if is_instance_valid(device):
		if enabled:
			device.enter_inspection()
		else:
			device.exit_inspection()


func _exit_tree() -> void:
	set_inspecting(false)
