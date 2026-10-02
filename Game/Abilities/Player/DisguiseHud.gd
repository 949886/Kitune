extends CanvasLayer
class_name DisguiseHud

@onready var _status_label: Label = $Overlay/Status
@onready var _hint_label: Label = $Overlay/Hint
@onready var _wheel: DisguiseRadialMenu = $Overlay/Wheel

var _ability: DisguiseAbility
var _was_menu_open := false
var _menu_center := Vector2.ZERO


func _ready() -> void:
	# The scene also starts hidden so its full-viewport Controls cannot be picked
	# through the player instance in the 2D editor, where this script does not run.
	# Runtime visibility follows the ability's menu state in _process().
	visible = false
	_resolve_ability()


func _process(_delta: float) -> void:
	_resolve_ability()
	if _ability == null:
		visible = false
		return

	visible = _ability.is_menu_open
	if not visible:
		_was_menu_open = false
		return

	if not _was_menu_open:
		_menu_center = get_viewport().get_mouse_position()
		_wheel.set_menu_center(_menu_center)
		_menu_center = _wheel.get_menu_center()
		_layout_overlay(_menu_center)
		_was_menu_open = true

	_status_label.text = _ability.get_status_text()
	_hint_label.text = "Hold E, aim with mouse, release to confirm"
	_wheel.set_ability(_ability)
	_layout_overlay(_menu_center)


func _resolve_ability() -> void:
	if _ability != null and is_instance_valid(_ability):
		return
	var player: Node = get_parent()
	if player == null:
		return
	_ability = player.get_node_or_null("DisguiseAbility") as DisguiseAbility
	if _ability != null:
		_wheel.set_ability(_ability)


func _layout_overlay(center: Vector2) -> void:
	_status_label.position = center + Vector2(-140.0, -30.0)
	_hint_label.position = center + Vector2(-180.0, 12.0)
