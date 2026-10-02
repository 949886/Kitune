extends Control
## F6 animation desk. Uses the same skin sampler as the playable INARI actor;
## playback, frame scrubbing and mirrored poses can be reviewed without a level.

const Animator = preload("res://Samples/ArtDirection/Runtime/InariAnimation.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
@export_file("*.json") var profile_path := "res://Game/Characters/WhiteSailor/appearance.json"

var profile: Dictionary
var actors: Array[Sprite2D] = []
var hero: Sprite2D
var action_picker: OptionButton
var status: Label
var scrubber: HSlider
var playing := true
var speed := 1.0
var drawing_count := 0


func _ready() -> void:
	get_window().size = Vector2i(1400, 900)
	profile = Assets.read_json(profile_path)
	for sheet: String in profile.sheets:
		var grid: Array = profile.sheets[sheet].get("grid", profile.grid)
		drawing_count += int(grid[0]) * int(grid[1])
	var backdrop := ColorRect.new()
	backdrop.color = Color("0d1422")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_label("CHARACTER / 01", Vector2(44, 26), 16, Color("91b8c5"))
	_label(profile.display_name, Vector2(44, 54), 34)
	_label("INARI  ·  动作预览", Vector2(1090, 68), 20, Color("bac7de"))
	_panel(Rect2(40, 125, 435, 625), Color("172337"))
	_label("REFERENCE PROPORTIONS", Vector2(62, 143), 13, Color("91b8c5"))
	_label("白发 / 紫瞳 / 水手服", Vector2(62, 169), 18)
	_line(Vector2(65, 685), Vector2(451, 685), Color("35506a"))
	hero = _actor("idle", Vector2(237, 680), 8.0)
	_label("实际角色等比放大 ×8", Vector2(62, 715), 15, Color("bac7de"))
	for index in profile.preview_actions.size():
		var action: Dictionary = profile.preview_actions[index]
		var origin := Vector2(495 + (index % 3) * 290, 125 + (index / 3) * 320)
		_panel(Rect2(origin, Vector2(270, 305)), Color("141f31"))
		_label("0%d / %s" % [index + 1, action.title], origin + Vector2(18, 14), 18)
		_label(action.clip, origin + Vector2(18, 45), 13, Color("91b8c5"))
		_line(origin + Vector2(20, 265), origin + Vector2(250, 265), Color("2c4058"))
		var actor := _actor(action.clip, origin + Vector2(125, 258), 2.9)
		actor.set_meta("preview_phase", action.get("phase", 0.3))
		_label("%d 帧" % profile.sequences[profile.clips[action.clip].sequence].cells.size(), origin + Vector2(18, 279), 12, Color("9cacbf"))
	_build_controls()
	if OS.get_cmdline_user_args().has("capture"):
		call_deferred("_capture")


func _actor(clip: String, foot: Vector2, zoom: float) -> Sprite2D:
	var rig := Node2D.new()
	rig.position = foot
	rig.scale = Vector2.ONE * zoom
	add_child(rig)
	var actor := Animator.new()
	actor.appearance_path = profile_path
	# The desk has no collision body: place hand-anchored actions inside the
	# same viewing area as the standing silhouette instead of below its floor.
	actor.ceiling_origin = Vector2(0.0, -55.0)
	actor.wall_origin = Vector2(18.0, 0.0)
	rig.add_child(actor)
	# The asset desk shows the authored palette. Real levels apply scene lights.
	actor.material = null
	actor.clips.BackIDLE = Assets.read_json(Assets.ROOT + "shrine_ambient.json").player_idle
	actor.play(clip, true)
	actors.append(actor)
	return actor


func _build_controls() -> void:
	action_picker = OptionButton.new()
	action_picker.position = Vector2(40, 781)
	action_picker.size = Vector2(270, 40)
	var names: Array = profile.clips.keys()
	names.sort()
	for name: String in names:
		action_picker.add_item(name)
		if name == "idle":
			action_picker.select(action_picker.item_count - 1)
	action_picker.item_selected.connect(func(index: int) -> void: hero.play(action_picker.get_item_text(index), true))
	add_child(action_picker)
	var pause := Button.new()
	pause.text = "暂停 / 播放"
	pause.position = Vector2(327, 781)
	pause.size = Vector2(130, 40)
	pause.pressed.connect(func() -> void: playing = not playing)
	add_child(pause)
	var flip := CheckButton.new()
	flip.text = "朝左"
	flip.position = Vector2(480, 781)
	flip.toggled.connect(_set_facing)
	add_child(flip)
	var replay := Button.new()
	replay.text = "重播 R"
	replay.position = Vector2(582, 781)
	replay.size = Vector2(96, 40)
	replay.pressed.connect(_replay)
	add_child(replay)
	var rate := HSlider.new()
	rate.position = Vector2(760, 790)
	rate.size = Vector2(200, 24)
	rate.min_value = 0.1
	rate.max_value = 2.0
	rate.step = 0.05
	rate.value = speed
	rate.value_changed.connect(func(value: float) -> void: speed = value)
	add_child(rate)
	_label("速度", Vector2(700, 787), 15, Color("bac7de"))
	scrubber = HSlider.new()
	scrubber.position = Vector2(1110, 790)
	scrubber.size = Vector2(230, 24)
	scrubber.min_value = 0.0
	scrubber.max_value = 1.0
	scrubber.step = 0.001
	scrubber.value_changed.connect(_scrub)
	add_child(scrubber)
	_label("逐帧 ← →", Vector2(1010, 787), 15, Color("bac7de"))
	status = _label("", Vector2(40, 845), 16, Color("9cacbf"))


func _set_facing(left: bool) -> void:
	for actor in actors:
		actor.facing = -1.0 if left else 1.0
		actor._refresh_frame()


func _scrub(value: float) -> void:
	playing = false
	hero.elapsed = value * float(hero.clips[hero.clip_name].length)
	hero._refresh_frame()


func _process(delta: float) -> void:
	if hero == null:
		return
	if playing:
		for actor in actors:
			# Attack, landing and death clips have distinct start/end poses.
			# Auto-wrapping them creates a jump that never occurs in gameplay.
			# Hold their final frame; only clips marked loop use cyclic playback.
			if not actor.finished():
				actor.advance(delta * speed)
	var clip: Dictionary = hero.clips[hero.clip_name]
	var time := fmod(hero.elapsed, float(clip.length)) if clip.loop else minf(hero.elapsed, float(clip.length))
	var frame: Dictionary = hero.appearance.sample(hero.clip_name, clip, time)
	status.text = "%d 张透明单帧 · %d 个状态 · %.2f× · %s / 第 %d 帧 · %s" % [drawing_count, profile.clips.size(), speed, hero.clip_name, frame.index + 1, "循环" if clip.loop else "单次动作，结束后停帧（R 重播）"]
	scrubber.set_value_no_signal(time / float(clip.length))


func _replay() -> void:
	hero.play(hero.clip_name, true)
	playing = true


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# Arrow keys step artwork even when the slider has keyboard focus. Let an
	# open action menu keep its own arrow navigation until the user chooses.
	if action_picker != null and action_picker.get_popup().visible:
		return
	if event.keycode == KEY_R:
		_replay()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		var clip: Dictionary = hero.clips[hero.clip_name]
		var time := fmod(hero.elapsed, float(clip.length)) if clip.loop else minf(hero.elapsed, float(clip.length))
		var sampled: Dictionary = hero.appearance.sample(hero.clip_name, clip, time)
		var mapping: Dictionary = profile.clips[hero.clip_name]
		var count: int = profile.sequences[mapping.sequence].cells.size()
		var index := wrapi(int(sampled.index) + (-1 if event.keycode == KEY_LEFT else 1), 0, count)
		var phase := float(mapping.frame_times[index]) if mapping.has("frame_times") else float(index) / count
		# Sample inside the key's interval to avoid a floating-point value just
		# before the boundary when stepping a short, nonuniform attack frame.
		_scrub(minf(phase + 0.00001, 1.0))
		get_viewport().set_input_as_handled()


func _label(text: String, at: Vector2, font_size: int, color := Color("edf2fa")) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _panel(rect: Rect2, color: Color) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)


func _line(from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.default_color = color
	line.width = 1.0
	add_child(line)


func _capture() -> void:
	playing = false
	for actor in actors:
		actor.elapsed = float(actor.clips[actor.clip_name].length) * float(actor.get_meta("preview_phase", 0.0))
		actor._refresh_frame()
	for frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := profile_path.get_base_dir().path_join("Previews/character_preview.png")
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("CHARACTER_PREVIEW_PASS ", path)
	get_tree().quit()
