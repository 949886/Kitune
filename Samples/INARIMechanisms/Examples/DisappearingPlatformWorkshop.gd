extends Node2D
## Practice geometry belongs to the host. The device scenes contain only source
## platform data and do not know this layout, player controller, UI or retry key.
@export var ledges: Array[Rect2] = [Rect2(32, 500, 148, 60), Rect2(870, 230, 130, 330)]
@onready var player: CharacterBody2D = $Player
@onready var platforms: Array[Node] = [$PlatformA, $PlatformB, $PlatformC]
var label: Label


func _ready() -> void:
	for ledge in ledges:
		var body := StaticBody2D.new()
		var collision := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = ledge.size
		collision.shape = box
		body.position = ledge.get_center()
		body.add_child(collision)
		add_child(body)
	var camera := Camera2D.new()
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	add_child(camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 20)
	ui.add_child(label)
	queue_redraw()


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	for index in platforms.size():
		var platform: Node = platforms[index]
		var text: String = ["可踩踏", "收起倒计时", "等待恢复"][platform.state]
		var remaining: float = platform.disappear_after - platform.elapsed if platform.state == 1 else platform.recover_after - platform.elapsed
		lines.append("%s · %s%s" % [char(65 + index), text, " %.2f s" % maxf(remaining, 0.0) if platform.state != 0 else ""])
	label.text = "INARI · 限时消失平台\nA / D 移动 · 空格跳跃 · R 重试\n踩踏后约 1.82 秒收起，1.25 秒后恢复\n" + "    ".join(lines)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("101b22"))
	for x in range(40, 1024, 120):
		draw_line(Vector2(x, 175), Vector2(x, 560), Color("243239"), 2)
	for ledge in ledges:
		draw_rect(ledge, Color("3c4c51"))
		draw_line(ledge.position, ledge.position + Vector2(ledge.size.x, 0), Color("c5ab76"), 3)
	draw_line(Vector2(0, 570), Vector2(1024, 570), Color("b75645"), 2)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		player.position = Vector2(120, 500)
		player.velocity = Vector2.ZERO
		for platform: Node in platforms:
			platform.reset()
