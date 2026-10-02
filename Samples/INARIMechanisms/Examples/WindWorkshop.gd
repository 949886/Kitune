extends Node2D
## Explicit host wiring: both stations share one character-side buff instance.
@onready var player: CharacterBody2D = $Player
@onready var target: StaticBody2D = $Target
@onready var first: Node2D = $First
@onready var second: Node2D = $Second
var status: Label
var activation_count := 0


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
	title.text = "INARI · 风增益装置"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · 空格跳跃 · J 攻击练习目标 · E 重置目标\n经过装置获得逐渐衰减的加速；击败目标升级已有增益。每个装置只补一次体力。"
	box.add_child(instructions)
	status = Label.new()
	box.add_child(status)
	for station: Node in [first, second]:
		station.bind_actor(player, player.buff.request_from_station, player.is_spawning)
		station.stamina_requested.connect(func(actor, amount): actor.add_stamina(amount))
		station.story_heal_requested.connect(func(actor, amount): actor.heal_story(amount))
		station.stamina_feedback_requested.connect(func(actor): actor.station_feedback())
		station.activated.connect(func(_actor): activation_count += 1)
	target.defeated.connect(_defeated)


func _defeated(attacker: Node) -> void:
	if attacker == player:
		player.buff.notify_player_kill()


func _process(_delta: float) -> void:
	status.text = (
		"增益 %d 级  ·  额外速度 %.1f px/s  ·  体力 %.0f / %.0f"
		% [player.buff.level, player.buff.extra_speed, player.stamina, player.maximum_stamina]
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_E
	):
		target.reset()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(20, 400, 984, 56), Color("39474e"))
	draw_line(Vector2(20, 400), Vector2(1004, 400), Color("8b9a92"), 3)
