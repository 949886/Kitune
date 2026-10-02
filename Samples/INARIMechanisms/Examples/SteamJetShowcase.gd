extends Node2D
## F6: a standalone exhibit using only resources inside this package.
const Exposure = preload("../Core/Native/Shaders/OriginalExposure.gdshader")
var devices: Array[Node] = []
var exposure_material: ShaderMaterial


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(480, 270)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 540.0
	# The main exhibit uses the tutorial ceiling instance. Smaller temple
	# instances demonstrate independent state and host-authored installation.
	for jet: Node in [$TutorialFlame, $TempleJet, $SideJet]:
		devices.append(jet)
	var exposure := CanvasLayer.new()
	exposure.layer = 1
	add_child(exposure)
	var screen := ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exposure.add_child(screen)
	exposure_material = ShaderMaterial.new()
	exposure_material.shader = Exposure
	var brightness: Dictionary = devices[0].source.preview_brightness
	exposure_material.set_shader_parameter("exposure_stops",
		(float(brightness.default_slider) + float(brightness.exposure_offset)) * float(brightness.exposure_scale))
	exposure_material.set_shader_parameter("linear_framebuffer", get_viewport().use_hdr_2d)
	screen.material = exposure_material
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	var column := VBoxContainer.new()
	column.position = Vector2(24, 20)
	ui.add_child(column)
	var title := Label.new()
	title.text = "INARI · 教程喷火装置"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "左：教程倒挂火柱　　右：神殿喷口的两种安装方向\n三个实例可独立开关；关闭后余焰自然消散。"
	column.add_child(subtitle)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for index in devices.size():
		var button := Button.new()
		button.text = "开关装置 %d" % (index + 1)
		button.pressed.connect(devices[index].toggle)
		buttons.add_child(button)
	var brightness_button := CheckButton.new()
	brightness_button.text = "原版曝光"
	brightness_button.button_pressed = true
	brightness_button.toggled.connect(func(enabled: bool): screen.visible = enabled)
	buttons.add_child(brightness_button)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("080b10"))
	draw_rect(Rect2(96, 130, 402, 410), Color("100c09"))
	draw_line(Vector2(96, 140), Vector2(498, 140), Color("3c3020"), 2.0)
	draw_line(Vector2(96, 420), Vector2(245, 420), Color("3c3020"), 3.0)
	draw_line(Vector2(355, 420), Vector2(498, 420), Color("3c3020"), 3.0)
	draw_line(Vector2(540, 145), Vector2(540, 500), Color("25303c"), 1.0)
