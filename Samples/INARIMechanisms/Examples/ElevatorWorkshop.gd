extends Node2D
## Standalone host keeps the ride in one scene so the physical endpoint can be
## exercised. The original mid-route scene-exit signal is observed separately.
@onready var elevator: Node2D = $Elevator
@onready var player: CharacterBody2D = $Player
var camera: Camera2D
var caption: Label
var hint: Label
var destination := ""
var exit_requests := 0
var recalls := 0
var completed := false


func _ready() -> void:
	camera = Camera2D.new()
	add_child(camera)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	camera.position = Vector2(512, player.position.y - 144)
	# The sample landings derive their heights from the source cabin and travel.
	var floor_height: float = elevator.position.y + elevator.platform.bounds.position.y
	var left_edge: float = elevator.position.x + elevator.platform.bounds.position.x
	var right_edge: float = elevator.position.x + elevator.platform.bounds.end.x
	_floor(Rect2(20, floor_height, left_edge - 20, 40))
	_floor(
		Rect2(right_edge, floor_height + elevator.settings.travel_offset.y, 1004 - right_edge, 40)
	)
	elevator.bind_passenger(player, $Player/Body)
	elevator.started.connect(func(): caption.text = "门已关闭，电梯等待后启动")
	elevator.arrived.connect(func(): caption.text = "轿厢已到站，等待门打开")
	elevator.doors_changed.connect(_doors_changed)
	elevator.scene_exit_requested.connect(_scene_exit)
	elevator.projectile_recall_requested.connect(func(_actor): recalls += 1)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 单次启动电梯"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · 空格跳跃 · 进入轿厢后按 F 启动\n等待两秒后上升，到站后向右走出。按钮只能使用一次。"
	box.add_child(instructions)
	caption = Label.new()
	caption.text = "从左侧走进轿厢，接近中间按钮"
	box.add_child(caption)
	hint = Label.new()
	box.add_child(hint)
	queue_redraw()


func _floor(rectangle: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rectangle.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rectangle.size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _doors_changed(closed: bool) -> void:
	if not closed:
		caption.text = "门已打开，可以向右离开轿厢"


func _scene_exit(_actor: Node, key: String) -> void:
	exit_requests += 1
	destination = key
	caption.text = "已经过原版换场景位置；本展厅继续演示完整到站"


func _process(_delta: float) -> void:
	camera.position.y = player.position.y - 144
	hint.text = "F  启动电梯" if elevator.can_interact(player) else ""
	if not completed and elevator.platform.arrival_count > 0 and player.position.x > 860:
		completed = true
		caption.text = "搭乘与出梯完成"


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_F
	):
		elevator.interact(player)


func _draw() -> void:
	if not is_instance_valid(elevator) or not is_instance_valid(elevator.platform):
		return
	var start: float = elevator.position.y + elevator.platform.bounds.position.y
	var finish: float = start + elevator.settings.travel_offset.y
	var left: float = elevator.position.x + elevator.platform.bounds.position.x
	var right: float = elevator.position.x + elevator.platform.bounds.end.x
	draw_rect(Rect2(0, finish - 500, 1024, start - finish + 1050), Color("121820"))
	draw_rect(Rect2(left, finish - 180, right - left, start - finish + 400), Color("202932"))
	for y in range(int(finish - 180), int(start + 200), 80):
		draw_line(Vector2(left + 3, y), Vector2(right - 3, y), Color("293640"), 2)
	for rectangle in [Rect2(20, start, left - 20, 40), Rect2(right, finish, 1004 - right, 40)]:
		draw_rect(rectangle, Color("39474e"))
		draw_line(
			rectangle.position,
			rectangle.position + Vector2(rectangle.size.x, 0),
			Color("8b9a92"),
			3
		)
	draw_line(Vector2(930, finish), Vector2(930, finish - 70), Color("80e8d9"), 3)
