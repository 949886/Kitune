extends Node2D
## Host example owns spawn conversion, health, camera and UI. The save marker
## below is a teaching aid: the selected original checkpoint has no active art.
@onready var checkpoint: Node2D = $Checkpoint
@onready var hazard: Node2D = $SpikeStrip
@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $Enemy
var caption: Label
var saves := 0
var feedback_count := 0


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 存档点与热阱"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · 空格跳跃 · R 复活 · I 无敌 4 秒 · E 敌人走入热阱\n穿过青色标记保存一次；存档不回血。站在热阱中，无敌结束仍会受伤。"
	box.add_child(instructions)
	caption = Label.new()
	box.add_child(caption)
	checkpoint.bind_actor(player, player.can_save)
	checkpoint.saved.connect(_saved)
	hazard.register_player(player, player.take_damage, player.can_take_damage)
	hazard.register_enemy(enemy, enemy.take_damage, enemy.can_take_damage)
	hazard.feedback_requested.connect(func(_kind: String): feedback_count += 1)
	player.hurt.connect(func(): caption.text = "已触发热阱，按 R 回到存档位置")
	caption.text = "向右穿过存档标记，当前生命 37 / 100"


func _saved(actor: Node2D, payload: Dictionary) -> void:
	saves += 1
	actor.save_checkpoint(payload)
	caption.text = "位置已保存一次，生命仍为 %d / 100" % actor.health
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			player.respawn(Vector2(100, 400))
			caption.text = "已由示例宿主复活；存档点仍保持已使用状态"
		KEY_I:
			if not player.dead:
				player.invulnerable_seconds = 4
				caption.text = "临时无敌 4 秒（示例调试控制）"
		KEY_E:
			enemy.respawn(Vector2(950, 400))
			enemy.left = true


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(20, 400, 984, 56), Color("39474e"))
	draw_line(Vector2(20, 400), Vector2(1004, 400), Color("8b9a92"), 3)
	if is_instance_valid(checkpoint):
		var point: Vector2 = checkpoint.position
		var color := Color("80e8d9") if saves > 0 else Color("527f85")
		draw_line(point, point + Vector2(0, -90), color, 2)
		draw_circle(point + Vector2(0, -94), 6, color, false, 2)
