extends Node2D
## Practice geometry belongs to the host. The device scenes contain only source
## platform data and do not know this layout, player controller, UI or retry key.
const DemoLayout = preload("../Devices/DisappearingPlatform3D/Examples/DemoLayout.gd")
@export var ledges: Array[Rect2] = [Rect2(32, 500, 148, 60), Rect2(870, 230, 130, 330)]
@onready var player: CharacterBody2D = $Player
@onready var platforms: Array[Node] = [$PlatformA, $PlatformB, $PlatformC]
var label: Label
var demo_layout: Node
var inspecting := false
var _player_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT


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
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	demo_layout = DemoLayout.new()
	add_child(demo_layout)
	demo_layout.configure(Vector2(1024, 576), Color("101b22"), label)
	queue_redraw()


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	for index in platforms.size():
		var platform: Node = platforms[index]
		var text: String = ["可踩踏", "收起倒计时", "等待恢复"][platform.state]
		var remaining: float = platform.disappear_after - platform.elapsed if platform.state == 1 else platform.recover_after - platform.elapsed
		lines.append("%s · %s%s" % [char(65 + index), text, " %.2f s" % maxf(remaining, 0.0) if platform.state != 0 else ""])
	var controls := "自由观察全部平台 · 鼠标拖动旋转 · 滚轮缩放 · V 返回 · R 重试并返回" if inspecting else "A / D 移动 · 空格跳跃 · R 重试 · V 自由观察 3D"
	label.text = "INARI · 3D 限时消失平台\n%s\n踩踏后约 1.82 秒收起，1.25 秒后恢复\n" % controls + "    ".join(lines)


func _draw() -> void:
	for x in range(40, 1024, 120):
		draw_line(Vector2(x, 175), Vector2(x, 560), Color("243239"), 2)
	for ledge in ledges:
		draw_rect(ledge, Color("3c4c51"))
		draw_line(ledge.position, ledge.position + Vector2(ledge.size.x, 0), Color("c5ab76"), 3)
	draw_line(Vector2(0, 570), Vector2(1024, 570), Color("b75645"), 2)


# _input runs before WorkshopPlayer's _unhandled_key_input. Do not place this
# gate in another unhandled callback, where sibling dispatch can leak a jump.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V:
			set_inspecting(not inspecting)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			set_inspecting(false)
			_clear_player_input()
			player.position = Vector2(120, 500)
			player.velocity = Vector2.ZERO
			for platform: Node in platforms:
				platform.reset()
			get_viewport().set_input_as_handled()
			return
	if inspecting:
		# Pass screen-space drag deltas unchanged at every camera/window scale.
		for platform: Node in platforms:
			platform.handle_inspection_input(event)
		get_viewport().set_input_as_handled()


## All three cameras orbit independently around their own platform origins.
## Only the actor is frozen; device animation/activation/recovery keep running.
func set_inspecting(enabled: bool) -> void:
	if inspecting == enabled:
		return
	inspecting = enabled
	if is_instance_valid(player):
		_clear_player_input()
		if enabled:
			_player_process_mode = player.process_mode
			player.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			player.process_mode = _player_process_mode
	for platform: Node in platforms:
		if is_instance_valid(platform):
			if enabled:
				platform.enter_inspection()
			else:
				platform.exit_inspection()


func _clear_player_input() -> void:
	# A key held on entry or released while inspecting must never remain stuck.
	player.left = false
	player.right = false
	player.pending_jump = false
	player.pending_attack = false
	player.attack_remaining = 0.0
	player.queue_redraw()


func _exit_tree() -> void:
	set_inspecting(false)
