extends "PortalRoom.gd"
## Host geometry is intentionally compact; source audio values remain intact.
const Zone = preload("../Devices/EnvironmentAudio/AudioParameterZone.gd")
@export var regions: Array[Dictionary] = []
@onready var player: CharacterBody2D = $Player
@onready var audio: Node = $Audio
var zones: Array[Area2D] = []
var label: Label


func _ready() -> void:
	super._ready()
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 22)
	ui.add_child(label)
	for region: Dictionary in regions:
		for preset: Resource in region.presets:
			var zone := Zone.new()
			zone.settings = preset.duplicate(true)
			zone.settings.trigger_size = region.size
			zone.settings.trigger_offset = Vector2.ZERO
			zone.position = region.position
			zone.bind_actor(player)
			zone.bind_audio(audio)
			zone.entered.connect(_show_region.bind(region.title))
			add_child(zone)
			zones.append(zone)
	_show_region("向右走进室内与室外区域")
	queue_redraw()


func _show_region(value: String) -> void:
	label.text = "INARI · 环境音区域\nA / D 移动 · 空格跳跃 · R 重试\n" + value + " · 离开后保留参数，另一片区域进入时切换"


func _draw() -> void:
	super._draw()
	for region: Dictionary in regions:
		draw_rect(Rect2(region.position - region.size / 2, region.size), region.color)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		call_deferred("_retry")


func _retry() -> void:
	var next: Node = load(get_script().resource_path.get_base_dir() + "/EnvironmentWorkshop.tscn").instantiate()
	var host := get_parent()
	if host.has_method("replace_exhibit"): host.replace_exhibit(self, next)
	else:
		host.remove_child(self)
		queue_free()
		host.add_child(next)
