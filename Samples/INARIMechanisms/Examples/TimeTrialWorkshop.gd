extends Node2D
## Example host connects portable endpoints, doors, camera, reward and saves.
## Its short practice layout is editable; the source timer remains 30 seconds.
const Trial = preload("../Devices/TimeTrial/TimeTrial.tscn")
const Preview = preload("../Devices/TimeTrial/RoutePreview.tscn")
const Door = preload("../Devices/MachineDoor/MachineDoor.tscn")
const Reward = preload("../Devices/HiddenReward/HiddenReward.tscn")
@export var start_position := Vector2(220, 335)
@export var finish_position := Vector2(1000, 335)
@export var terminal_scale := 0.7
@export var gate_positions: Array[Vector2] = [Vector2(420, 400), Vector2(1180, 400)]
@export var reward_position := Vector2(1350, 365)
@export var route_positions: Array[Vector2] = [
	Vector2(220, 288), Vector2(600, 288), Vector2(1000, 288), Vector2(1350, 288)
]
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera
var trial: Node2D
var preview: Node
var reward: Node2D
var gates: Array[Node2D] = []
var save_data: Dictionary = {}
var reward_count := 0
var money := 0
var caption: Label
var attempt: Node2D
var checkpoint := Vector2.ZERO


func _ready() -> void:
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 限时挑战"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var help := Label.new()
	help.text = "A / D 移动 · 空格跳跃 · F 启动 / 确认终点\nR 重试（保留已看预览与领取记录）· N 重新体验 · H 模拟存档后死亡"
	box.add_child(help)
	caption = Label.new()
	box.add_child(caption)
	_reload()


func _reload() -> void:
	if is_instance_valid(attempt):
		trial.cancel()
		remove_child(attempt)
		attempt.queue_free()
	player.set_input_enabled(true)
	player.position = Vector2(100, 400)
	camera.position = Vector2(512, 288)
	attempt = Node2D.new()
	add_child(attempt)
	gates.clear()
	for point in gate_positions:
		var gate := Door.instantiate()
		gate.position = point
		gate.scale = Vector2.ONE * 0.5
		attempt.add_child(gate)
		gates.append(gate)
	trial = Trial.instantiate()
	trial.settings = trial.settings.duplicate()
	trial.settings.intro_seen = save_data.get("intro_seen", false)
	var dest: Dictionary = save_data.get("destination", {})
	trial.settings.destination_saved = not dest.is_empty()
	trial.settings.destination_time_over = dest.get("IsTimeOver", false)
	trial.settings.destination_enabled = dest.get("CollEnabled", true)
	attempt.add_child(trial)
	trial.starter.position = start_position
	trial.destination.position = finish_position
	for terminal: Node2D in [trial.starter, trial.destination]:
		terminal.scale = Vector2.ONE * terminal_scale
	trial.bind_actor(player)
	trial.start_door_requested.connect(gates[0].toggle)
	trial.reward_doors_requested.connect(gates[1].toggle)
	trial.checkpoint_requested.connect(func(_actor, point): checkpoint = point)
	trial.intro_save_requested.connect(func(): save_data.intro_seen = true)
	trial.destination_save_requested.connect(
		func(record, now):
			if now:
				save_data.destination = record
	)
	var source_stops: Array = trial.starter.document.record.camera_stops
	assert(route_positions.size() == source_stops.size())
	for i in route_positions.size():
		trial.route_override.append(
			{
				"position": to_global(route_positions[i]),
				"distance": source_stops[i].distance,
				"wait": source_stops[i].wait
			}
		)
	preview = Preview.instantiate()
	attempt.add_child(preview)
	preview.bind(trial, camera, player, player.set_input_enabled)
	reward = Reward.instantiate()
	reward.position = reward_position
	reward.settings = reward.settings.duplicate()
	reward.settings.initially_collected = save_data.get("reward", false)
	reward.bind_actor(player, $Player/Body)
	reward.reward_granted.connect(
		func(_actor, amount, _id):
			reward_count += amount
			save_data.reward = true
	)
	reward.currency_requested.connect(func(_actor, amount): money += amount)
	attempt.add_child(reward)
	# Door persistence is a host responsibility too; do not replay success.
	if not dest.is_empty() and not dest.get("IsTimeOver", false):
		gates[1].open()


func _process(_delta: float) -> void:
	if not is_instance_valid(trial):
		return
	if trial.state != "preview":
		camera.position = Vector2(clampf(player.position.x, 512, 1040), 288)
	var labels := {
		"ready": "靠近左侧终端按 F",
		"preview": "预览路线",
		"running": "到达右侧终端后按 F",
		"success": "奖励门已打开",
		"failed": "挑战失败 · R 重试",
		"cancelled": "挑战取消"
	}
	caption.text = (
		"%s · %02d:%02d · 奖励 %d · 光点 %d"
		% [
			labels.get(trial.state, trial.state),
			int(trial.remaining / 60),
			int(fmod(trial.remaining, 60)),
			reward_count,
			money
		]
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F:
			if player.input_enabled:
				if not trial.starter.interact(player):
					trial.destination.interact(player)
		KEY_R:
			# Timeout itself does not request an immediate source save; restarting
			# before another save reloads the prior room state and skips the intro.
			_reload()
		KEY_N:
			save_data.clear()
			reward_count = 0
			money = 0
			_reload()
		KEY_H:
			trial.notify_checkpoint_saved()
			trial.notify_actor_died()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1560, 576), Color("16272c"))
	draw_rect(Rect2(20, 400, 1520, 56), Color("405655"))
	draw_line(Vector2(20, 400), Vector2(1540, 400), Color("91b0a1"), 3)
