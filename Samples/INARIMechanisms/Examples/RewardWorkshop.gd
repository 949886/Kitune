extends Node2D
## Host owns inventory and a session-only save dictionary; the devices own
## visuals, trigger state and fragment trajectories. R demonstrates restoration.
const Reward = preload("../Devices/HiddenReward/HiddenReward.tscn")
@onready var player: CharacterBody2D = $Player
@onready var station: Node2D = $Station
@export var reward_positions: Array[Vector2] = [Vector2(320, 365), Vector2(820, 365)]
var rewards: Array[Node] = []
var saved: Dictionary = {}
var reward_count := 0
var money := 0
var refreshes := 0
var caption: Label


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	station.bind_actor(player, player.buff.request_from_station)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 隐藏奖励与追踪光点"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var help := Label.new()
	help.text = "A / D 移动 · 空格跳跃 · 接触奖励即可领取\n先领取左侧奖励，再经过风装置领取右侧奖励。R 重载已保存状态。"
	box.add_child(help)
	caption = Label.new()
	box.add_child(caption)
	_replace_rewards()


func _replace_rewards() -> void:
	for reward: Node in rewards:
		remove_child(reward)
		reward.queue_free()
	rewards.clear()
	for index in reward_positions.size():
		var reward := Reward.instantiate()
		reward.position = reward_positions[index]
		reward.reward_id = "practice-reward-" + str(index)
		reward.settings = reward.settings.duplicate(true)
		reward.settings.initially_collected = saved.get(reward.reward_id, false)
		reward.bind_actor(player, $Player/Body)
		reward.reward_granted.connect(_granted)
		reward.currency_requested.connect(_currency)
		reward.renew_existing_buff_requested.connect(_refresh)
		add_child(reward)
		rewards.append(reward)


func _granted(_actor: Node2D, amount: int, id: String) -> void:
	reward_count += amount
	saved[id] = true


func _currency(_actor: Node2D, amount: int) -> void:
	money += amount


func _refresh(_actor: Node2D) -> void:
	if player.buff.refresh_existing():
		refreshes += 1


func _process(_delta: float) -> void:
	var reward_total := 0
	var currency_total := 0
	for reward: Node in rewards:
		reward_total += reward.settings.reward_amount
		currency_total += (
			reward.document.record.charges.size() * reward.settings.currency_per_fragment
		)
	caption.text = (
		"奖励 %d / %d · 光点 %d / %d · 风增益 %d 级 · 已续期 %d 次"
		% [reward_count, reward_total, money, currency_total, player.buff.level, refreshes]
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		_replace_rewards()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("16272c"))
	draw_rect(Rect2(20, 400, 984, 56), Color("405655"))
	draw_line(Vector2(20, 400), Vector2(1004, 400), Color("91b0a1"), 3)
