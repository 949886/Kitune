extends Node2D
## Source region sizes/parameters in a simple walkable host, not a source level.
const Rig = preload("../Devices/CameraZone/CameraZoneRig.gd")
@onready var player: CharacterBody2D = $Player
@onready var controller: Node = $Controller
@onready var distance_zone: Area2D = $Distance
@onready var fixed_zone: Area2D = $Fixed
var rig: Node
var caption: Label


func _ready() -> void:
	controller.bind_actor(player, func(): return player.global_position + Vector2(0, -16))
	distance_zone.bind_controller(controller)
	fixed_zone.bind_controller(controller)
	rig = Rig.new()
	add_child(rig)
	rig.bind_controller(controller, Vector2(0, -16))
	var ui := CanvasLayer.new()
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 24)
	ui.add_child(box)
	var title := Label.new()
	title.text = "INARI · 镜头区域"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var help := Label.new()
	help.text = "A / D 移动 · 空格跳跃 · R 重试\n穿过青色区域拉远视野；紫色区域固定纵向构图，离开后只触发一次。"
	box.add_child(help)
	caption = Label.new()
	box.add_child(caption)
	queue_redraw()


func _process(_delta: float) -> void:
	caption.text = "距离 %.2f  ·  %s" % [rig.renderer.camera_distance,
		"固定区域已消耗" if fixed_zone.consumed else ("固定构图" if fixed_zone.inside else ("视野拉远" if distance_zone.inside else "跟随角色"))]


func _draw() -> void:
	draw_rect(Rect2(-1200, -1200, 6400, 2400), Color("14252d"))
	for x in range(-800, 4400, 200):
		draw_line(Vector2(x, -200), Vector2(x, 400), Color("273c45"), 4)
	draw_rect(Rect2(-1000, 400, 6000, 80), Color("47605c"))
	for zone: Area2D in [distance_zone, fixed_zone]:
		var tint := Color(0.3, 0.85, 0.8, 0.15) if zone == distance_zone else Color(0.75, 0.5, 0.95, 0.15)
		var rect := Rect2(zone.settings.trigger_offset - zone.settings.trigger_size / 2, zone.settings.trigger_size)
		draw_set_transform_matrix(zone.transform)
		draw_rect(rect, tint)
		draw_rect(rect, Color(tint, 0.8), false, 0.04)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		call_deferred("_retry")


func _retry() -> void:
	var next: Node = load(get_script().resource_path.get_base_dir() + "/CameraZoneWorkshop.tscn").instantiate()
	var host := get_parent()
	if host.has_method("replace_exhibit"): host.replace_exhibit(self, next)
	else:
		host.remove_child(self)
		queue_free()
		host.add_child(next)
