extends "PortalRoom.gd"
## Compact example geometry exposes the original 35 + 20 unit range change.
@export var zone_size := Vector2(200, 170)
@export var zone_center := Vector2(320, 320)
@export var target_position := Vector2(990, 300)
@onready var player: CharacterBody2D = $Player
@onready var zone: Area2D = $Zone
@onready var projectile: Node2D = $Projectile
var label: Label
var hits := 0
var expired := 0


func _enter_tree() -> void:
	# Keep the original preset's behavior; only this host's practice layout differs.
	var configured: Area2D = get_node("Zone")
	configured.settings = configured.settings.duplicate(true)
	configured.settings.trigger_size = zone_size
	configured.settings.trigger_offset = Vector2.ZERO
	configured.position = zone_center


func _ready() -> void:
	super._ready()
	player.projectile = projectile
	zone.bind_actor(player)
	zone.bind_range(player.range_state)
	var target := StaticBody2D.new()
	target.position = target_position
	target.set_meta("range_target", true)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20, 200)
	shape.shape = box
	target.add_child(shape)
	add_child(target)
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 21)
	ui.add_child(label)
	player.range_state.distance_changed.connect(func(_v): _status())
	projectile.target_hit.connect(func(): hits += 1; _status())
	projectile.launched.connect(func(_limit): _status())
	projectile.retired.connect(func(reason):
		if reason == "range": expired += 1
		_status())
	_status()
	queue_redraw()


func _status() -> void:
	var scale_units: float = player.range_state.settings.pixels_per_unit
	label.text = "INARI · 苦无射程区域\nA / D 移动 · F 向面朝方向投掷 · 空格跳跃 · R 重试\n当前射程 %.0f 单位 · 本次投掷 %.0f 单位\n远墙命中 %d · 超距消失 %d · 走进蓝色区域后投掷更远" % [player.range_state.current_limit() / scale_units, projectile.captured_limit / scale_units, hits, expired]


func _draw() -> void:
	super._draw()
	draw_rect(Rect2(zone_center - zone_size / 2, zone_size), Color(0.3, 0.7, 0.8, 0.17))
	draw_rect(Rect2(target_position - Vector2(10, 100), Vector2(20, 200)), Color("cfaa6a"))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		call_deferred("_retry")


func _retry() -> void:
	var next: Node = load(get_script().resource_path.get_base_dir() + "/ShurikenDistanceWorkshop.tscn").instantiate()
	var host := get_parent()
	if host.has_method("replace_exhibit"): host.replace_exhibit(self, next)
	else:
		host.remove_child(self)
		queue_free()
		host.add_child(next)
