extends Node2D
## Wiring belongs to the host scene. Both levers operate the same door through
## a .tscn signal connection, demonstrating composition without object IDs.
@onready var door: Node = $Door
@onready var player: CharacterBody2D = $Player
var caption: Label


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(512, 428)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(984, 56)
	shape.shape = rectangle
	floor_body.add_child(shape)
	add_child(floor_body)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 机械门"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · 空格跳跃 · J 攻击拉杆\n两侧拉杆均可开关门；开启后等待门扇抬起再通过。"
	box.add_child(instructions)
	caption = Label.new()
	box.add_child(caption)
	door.state_changed.connect(func(_value: bool): _update_caption())
	door.passability_changed.connect(func(_value: bool): _update_caption())
	_update_caption()


func _update_caption() -> void:
	if door.is_passable():
		caption.text = "门已开启 · 可以通过"
	elif door.is_open():
		caption.text = "正在开启 · 碰撞尚未释放"
	else:
		caption.text = "门已关闭 · 通道阻挡"


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(20, 400, 984, 56), Color("39474e"))
	draw_line(Vector2(20, 400), Vector2(1004, 400), Color("8b9a92"), 3)
	draw_rect(Rect2(500, 154, 120, 246), Color("202b32"))
