extends Node2D
## Host scene owns physical platforms, training enemies and explicit wiring.
## No wave is cleared by a timer or a simulated completion notification.
const Target = preload("BattleTarget.gd")
const Arrivals = preload("../Devices/ArrivalEffect/ArrivalBatch.tscn")
@export var title_text := "INARI · 分波封锁房间"
@export_multiline var instruction_text := "A / D 移动 · 空格跳跃 · J 普通攻击 / K 重击 · R 重试\n进入后封门；击败上下层的两波练习目标，出口才会开启。"
@onready var encounter: Node2D = $Encounter
@onready var player: CharacterBody2D = $Player
@onready var entry: Node2D = $Entry
@onready var exit_door: Node2D = $Exit
@onready var contact: Node2D = $Contact
var enemies: Dictionary = {}
var caption: Label
var arrivals: Node2D
var cleanup_requests := 0
var completion_count := 0


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	for block: Node2D in $Platforms.get_children():
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = block.get_meta("size")
		shape.shape = rectangle
		body.add_child(shape)
		block.add_child(body)
	for key: String in encounter.settings.placements:
		var target := Target.new()
		target.position = to_local(encounter.to_global(encounter.settings.placements[key]))
		add_child(target)
		enemies[key] = target
		encounter.bind_enemy(key, target, target.set_active, target.set_peaceful)
		target.defeated.connect(func(actor: Node2D): encounter.notify_defeated(key, actor))
	contact.bind_actor(player)
	contact.contacted.connect(func(_actor): entry.call_deferred("toggle"))
	contact.outside_projectiles_cleanup_requested.connect(func(_actor): cleanup_requests += 1)
	encounter.completed.connect(_completed)
	arrivals = Arrivals.instantiate()
	add_child(arrivals)
	encounter.wave_arrival_requested.connect(arrivals.spawn_wave)
	var ui := CanvasLayer.new()
	add_child(ui)
	var column := VBoxContainer.new()
	column.position = Vector2(24, 20)
	ui.add_child(column)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var help := Label.new()
	help.text = instruction_text
	column.add_child(help)
	caption = Label.new()
	column.add_child(caption)
	encounter.state_changed.connect(_status)
	queue_redraw()


func _completed() -> void:
	completion_count += 1
	exit_door.open()


func _status(state: String, phase: int, remaining: int) -> void:
	if state == "complete":
		caption.text = "清场完成 · 等待门扇抬起后通过右侧出口"
	elif state == "phase_delay" or state == "spawn_wait" or state == "spawning":
		caption.text = "下一波正在入场"
	else:
		caption.text = "第 %d / %d 波 · 剩余 %d" % [phase + 1, encounter.settings.waves.size(), remaining]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		call_deferred("_restart")


func _restart() -> void:
	# Preserve an inherited workshop (e.g. delayed spawning) when retrying.
	var replacement: Node = load(scene_file_path).instantiate()
	if get_parent().has_method("replace_exhibit"):
		get_parent().replace_exhibit(self, replacement)
	else:
		get_parent().add_child(replacement)
		queue_free()


func _process(_delta: float) -> void:
	arrivals.custom_time_scale = encounter.custom_time_scale


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	for block: Node2D in $Platforms.get_children():
		var size: Vector2 = block.get_meta("size")
		draw_rect(Rect2(block.position - size / 2, size), Color("39474e"))
