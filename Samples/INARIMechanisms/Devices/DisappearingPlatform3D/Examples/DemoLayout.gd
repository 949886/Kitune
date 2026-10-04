extends Node
## Demo-local presentation. Keep physics in authored world units, fit the whole
## stage uniformly, and cover the extra space without changing project settings.
var design_size := Vector2.ONE
var camera: Camera2D
var background: ColorRect
var label: Label


func configure(stage_size: Vector2, background_color: Color, hud_label: Label) -> void:
	design_size = stage_size
	var backdrop := CanvasLayer.new()
	backdrop.name = "DemoBackground"
	backdrop.layer = -100
	add_child(backdrop)
	background = ColorRect.new()
	background.color = background_color
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(background)

	camera = Camera2D.new()
	camera.name = "DemoCamera"
	camera.position = design_size * 0.5
	add_child(camera)
	camera.make_current()

	var hud := CanvasLayer.new()
	hud.name = "DemoHUD"
	add_child(hud)
	label = hud_label
	if label.get_parent() != null:
		label.reparent(hud, false)
	else:
		hud.add_child(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	# This is the host viewport, never a device's fixed-resolution 3D SubViewport.
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_size := viewport_rect.size.max(Vector2.ONE)
	background.position = viewport_rect.position
	background.size = viewport_size
	var fit := minf(viewport_size.x / design_size.x, viewport_size.y / design_size.y)
	camera.zoom = Vector2.ONE * fit
	camera.force_update_scroll()

	# HUD uses screen coordinates, independently of world zoom/letterbox space.
	# Only small windows shrink the text; long control hints wrap within the view.
	var hud_scale := minf(1.0, minf(viewport_size.x / 720.0, viewport_size.y / 360.0))
	var margin := Vector2(24, 24) * hud_scale
	label.position = viewport_rect.position + margin
	label.scale = Vector2.ONE * hud_scale
	label.size = Vector2((viewport_size.x - margin.x * 2.0) / hud_scale, 0.0)
