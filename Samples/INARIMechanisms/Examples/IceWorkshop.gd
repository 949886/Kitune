extends Node2D
## Host-owned patrol actors demonstrate eligibility and timed recovery.
const IceBox = preload("../Devices/IceBox/IceBox.tscn")
@onready var ice: Node = $IceBox
@onready var player: CharacterBody2D = $Player
var caption: Label
var affected_count := 0


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	for rect: Rect2 in [Rect2(20, 420, 984, 56), Rect2(572, 70, 16, 400)]:
		var wall := StaticBody2D.new()
		wall.position = rect.get_center()
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		wall.add_child(shape)
		add_child(wall)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 冰冻装置"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · J 攻击装置 · R 更换装置\n青色表示冻结；紫色目标免疫，墙后和远处目标不会被冻结。"
	box.add_child(instructions)
	caption = Label.new()
	box.add_child(caption)
	_connect_device()


func _connect_device() -> void:
	for actor: Node2D in $Targets.get_children():
		ice.register_target(actor, actor.freeze, actor.can_freeze)
	ice.charge_started.connect(func(): caption.text = "正在蓄能")
	ice.discharged.connect(_discharged)
	caption.text = "靠近并攻击装置；附近目标正在移动"


func _discharged(affected: Array) -> void:
	affected_count = affected.size()
	caption.text = "已冻结 %d 个目标，%.1f 秒后恢复；装置只能触发一次" % [affected_count, ice.settings.freeze_seconds]


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		replace_device.call_deferred()


func replace_device() -> void:
	var pose: Transform2D = ice.transform
	remove_child(ice)
	ice.queue_free()
	ice = IceBox.instantiate()
	ice.transform = pose
	add_child(ice)
	ice.bind_observer(player, Vector2(0, -16))
	_connect_device()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(20, 420, 984, 56), Color("39474e"))
	draw_line(Vector2(20, 420), Vector2(1004, 420), Color("8b9a92"), 3)
	draw_rect(Rect2(572, 70, 16, 400), Color("55616b"))
