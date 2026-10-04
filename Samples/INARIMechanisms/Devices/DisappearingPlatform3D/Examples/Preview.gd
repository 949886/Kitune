extends Node2D
## Complete, copyable workshop. All play geometry is authored in Preview.tscn.
const DemoLayout = preload("DemoLayout.gd")
@onready var player: CharacterBody2D = $Player
@onready var platforms: Array[Node] = [$PlatformA, $PlatformB, $PlatformC]
# Keep the primary-device alias available to small embedding/inspection examples.
@onready var device: Node2D = $PlatformA
@onready var label: Label = $Label
var demo_layout: Node
var inspecting := false
var _player_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	for platform: Node in platforms:
		platform.bind_actor(player)
	demo_layout = DemoLayout.new()
	add_child(demo_layout)
	demo_layout.configure(Vector2(1024, 576), Color("101b22"), label)


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	for index in platforms.size():
		var platform: Node = platforms[index]
		var text: String = ["可踩踏", "收起倒计时", "等待恢复"][platform.state]
		var remaining: float = platform.disappear_after - platform.elapsed if platform.state == 1 else platform.recover_after - platform.elapsed
		lines.append("%s · %s%s" % [char(65 + index), text, " %.2f s" % maxf(remaining, 0.0) if platform.state != 0 else ""])
	var controls := "自由观察全部平台 · 鼠标拖动旋转 · 滚轮缩放 · V 返回 · R 重试并返回" if inspecting else "A / D 或方向键移动 · 空格跳跃 · R 重试 · V 自由观察 3D"
	label.text = "INARI · 3D 限时消失平台\n%s\n踩踏后约 %.2f 秒收起，%.2f 秒后恢复\n" % [controls, device.disappear_after, device.recover_after] + "    ".join(lines)


func _draw() -> void:
	for x in range(40, 1024, 120):
		draw_line(Vector2(x, 175), Vector2(x, 560), Color("243239"), 2)
	draw_line(Vector2(0, 570), Vector2(1024, 570), Color("b75645"), 2)


# This gate runs before the player's unhandled key input. Consume releases and
# mouse events as well, so inspection never queues a jump, move or attack.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V:
			set_inspecting(not inspecting)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			reset_demo()
			get_viewport().set_input_as_handled()
			return
	if inspecting:
		# Orbit deltas are viewport pixels, independent of the fitted world zoom.
		for platform: Node in platforms:
			platform.handle_inspection_input(event)
		get_viewport().set_input_as_handled()


func reset_demo() -> void:
	set_inspecting(false)
	_clear_player_input()
	player.position = Vector2(120, 500)
	player.velocity = Vector2.ZERO
	for platform: Node in platforms:
		platform.reset()


## Freeze only the actor: all platform countdowns and recovery keep running.
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
	player.clear_input()


func _exit_tree() -> void:
	set_inspecting(false)
