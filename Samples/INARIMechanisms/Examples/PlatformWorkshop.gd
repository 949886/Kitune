extends Node2D
## A playable assembly of two independent scenes. The signal connection lives
## in the host .tscn; neither device stores the other's path or native object ID.
@onready var platform: Node = $Platform
@onready var lever: Node = $Lever
@onready var player: CharacterBody2D = $Player
var caption: Label


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	for span in [Vector2(20, 280), Vector2(872, 1004)]:
		var floor_body := StaticBody2D.new()
		floor_body.position = Vector2((span.x + span.y) / 2, 428)
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(span.y - span.x, 56)
		shape.shape = rectangle
		floor_body.add_child(shape)
		add_child(floor_body)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 拉杆与移动平台"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · 空格跳跃 · J 攻击拉杆\n拨动拉杆后走上平台，搭乘到右岸；再次拨动可连续换向。"
	box.add_child(instructions)
	caption = Label.new()
	box.add_child(caption)
	platform.started.connect(func(): caption.text = "平台等待启动")
	platform.arrived.connect(func(): caption.text = "已到站")
	caption.text = "接近左侧拉杆"
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	for span in [Vector2(20, 280), Vector2(872, 1004)]:
		draw_rect(Rect2(span.x, 400, span.y - span.x, 56), Color("39474e"))
		draw_line(Vector2(span.x, 400), Vector2(span.y, 400), Color("8b9a92"), 3)
	draw_dashed_line(Vector2(280, 460), Vector2(872, 460), Color("445158"), 1, 7)
