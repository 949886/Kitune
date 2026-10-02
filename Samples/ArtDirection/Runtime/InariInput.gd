extends RefCounted
## Keep the original bindings inside this study, without editing project inputs.

const PREFIX := "inari_study_"
const BUTTON_ACTIONS := {
	"MS_Attack": "attack",
	"MS_Throw": "throw",
	"KB_Jump": "jump",
	"KB_Dash": "dash",
	"KB_ShurikenMove": "teleport",
	"KB_StrongAttack": "heavy_attack",
	"KB_Interactive": "interact",
	"GP_Attack": "attack",
	"GP_Jump": "jump",
	"GP_Dash": "dash",
	"GP_StrongAttack": "heavy_attack",
	"GP_Interactive": "interact",
	"GP_Throw&ShurikenMove": "pad_throw",
	"GP_ShurikenCancel": "cancel_projectile",
}
const PAD_BUTTONS := {
	"buttonSouth": JOY_BUTTON_A,
	"buttonNorth": JOY_BUTTON_Y,
	"leftShoulder": JOY_BUTTON_LEFT_SHOULDER,
	"rightShoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"rightStickPress": JOY_BUTTON_RIGHT_STICK,
	"dpad/left": JOY_BUTTON_DPAD_LEFT,
	"dpad/right": JOY_BUTTON_DPAD_RIGHT,
	"dpad/up": JOY_BUTTON_DPAD_UP,
	"dpad/down": JOY_BUTTON_DPAD_DOWN,
}


static func action(name: String) -> StringName:
	return StringName(PREFIX + name)


static func install(bindings: Array) -> void:
	for name in [
		"left",
		"right",
		"up",
		"down",
		"attack",
		"throw",
		"jump",
		"dash",
		"teleport",
		"heavy_attack",
		"interact",
		"pad_throw",
		"cancel_projectile"
	]:
		if not InputMap.has_action(action(name)):
			InputMap.add_action(action(name), 0.1)

	for binding: Dictionary in bindings:
		var name: String = BUTTON_ACTIONS.get(binding.action, "")
		if binding.action in ["KB_Horizontal", "GP_Horizontal"]:
			name = "left" if binding.name == "negative" else "right"
		elif binding.action in ["KB_Vertical", "GP_Vertical"]:
			name = "down" if binding.name == "negative" else "up"

		if name.is_empty() or str(binding.path).is_empty() or binding.isComposite:
			continue

		var event := _event_for_path(binding.path)
		if event != null and not InputMap.action_has_event(action(name), event):
			InputMap.action_add_event(action(name), event)

	# InariMovementInput handles the stick as one radial Vector2 control.


static func _event_for_path(path: String) -> InputEvent:
	if path.begins_with("<Keyboard>/"):
		var key := path.trim_prefix("<Keyboard>/")
		var event := InputEventKey.new()
		event.physical_keycode = (
			KEY_SHIFT if key == "leftShift" else OS.find_keycode_from_string(key)
		)
		return event

	if path.begins_with("<Mouse>/"):
		var event := InputEventMouseButton.new()
		event.button_index = (
			MOUSE_BUTTON_LEFT if path.ends_with("leftButton") else MOUSE_BUTTON_RIGHT
		)
		return event

	if path.begins_with("<Gamepad>/"):
		var key := path.trim_prefix("<Gamepad>/")
		if key in ["leftTrigger", "rightTrigger"]:
			var event := InputEventJoypadMotion.new()
			event.axis = JOY_AXIS_TRIGGER_LEFT if key == "leftTrigger" else JOY_AXIS_TRIGGER_RIGHT
			event.axis_value = 1.0
			return event

		if PAD_BUTTONS.has(key):
			var event := InputEventJoypadButton.new()
			event.button_index = PAD_BUTTONS[key]
			return event

	return null
