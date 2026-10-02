extends Node2D
## Deliberately simple host room, not the original game's level artwork.
const Portal = preload("../Devices/ScenePortal/ScenePortal.tscn")
@export var title := ""
@export var background := Color("15252d")
@export var portal_settings: Resource
@export var exit_center := Vector2(650, 330)
var portal: Node2D
var spawn := Vector2(180, 400)


func _ready() -> void:
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(512, 420)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1024, 40)
	shape.shape = rectangle
	floor_body.add_child(shape)
	add_child(floor_body)
	if portal_settings != null:
		portal = Portal.instantiate()
		portal.settings = portal_settings
		portal.position = exit_center - portal_settings.trigger_offset
		add_child(portal)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), background)
	for x in [90, 370, 930]:
		draw_rect(Rect2(x, 160, 24, 240), background.lightened(0.08))
	draw_rect(Rect2(0, 400, 1024, 40), Color("485957"))
	draw_line(Vector2(0, 400), Vector2(1024, 400), Color("9eb7ab"), 3)
	if portal_settings != null:
		# Visible host guide to an otherwise invisible authored trigger volume.
		var area := Rect2(
			exit_center - portal_settings.trigger_size / 2, portal_settings.trigger_size
		)
		draw_rect(area, Color(0.3, 0.9, 0.8, 0.12))
		draw_rect(area, Color("7bd6c3"), false, 2)
		draw_line(exit_center + Vector2(-20, 0), exit_center + Vector2(20, 0), Color("7bd6c3"), 3)
		draw_line(exit_center + Vector2(20, 0), exit_center + Vector2(10, -10), Color("7bd6c3"), 3)
