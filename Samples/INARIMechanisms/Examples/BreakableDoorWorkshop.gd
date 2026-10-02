extends Node2D
## Two source profiles, one independent device implementation. The controller
## issues ordinary/heavy hits through actual shape queries, without game globals.
const Wood = preload("../Devices/BreakableDoor/WoodDoor.tscn")
const Heavy = preload("../Devices/BreakableDoor/HeavyDoor.tscn")
@onready var wood: Node = $WoodDoor
@onready var heavy: Node = $HeavyDoor
@onready var player: CharacterBody2D = $Player
var caption: Label


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(512, 428)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(984, 56)
	shape.shape = rectangle
	floor_body.add_child(shape)
	add_child(floor_body)
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 可破坏门"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "A / D 移动 · J 普通攻击 · K 重击 · R 重置\n左侧木门可普攻打碎；右侧门需要重击。碎片落地后逐渐消散。"
	box.add_child(instructions)
	caption = Label.new()
	box.add_child(caption)
	_connect_doors()


func _connect_doors() -> void:
	wood.broken.connect(func(): caption.text = "木门已破坏，可以通过")
	heavy.impacted.connect(_heavy_impact)
	caption.text = "接近左侧木门"


func _heavy_impact(_interaction: int) -> void:
	caption.text = "重击门已破坏" if heavy.is_broken() else "普通攻击无法破坏此门，按 K 重击"


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		reset_doors.call_deferred()


func reset_doors() -> void:
	var poses: Array[Transform2D] = [wood.transform, heavy.transform]
	for door: Node in [wood, heavy]:
		remove_child(door)
		door.queue_free()
	wood = Wood.instantiate()
	heavy = Heavy.instantiate()
	wood.transform = poses[0]
	heavy.transform = poses[1]
	add_child(wood)
	add_child(heavy)
	player.position = Vector2(150, 400)
	player.velocity = Vector2.ZERO
	_connect_doors()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(20, 400, 984, 56), Color("39474e"))
	draw_line(Vector2(20, 400), Vector2(1004, 400), Color("8b9a92"), 3)
