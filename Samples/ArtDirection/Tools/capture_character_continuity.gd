extends SceneTree
## Render a real, fixed-root before/after playback. Raw PNG loading also makes
## the tool usable immediately after an asset build, before editor reimport.
## Optional before=... directory must contain appearance.json/frame_manifest.json/Sheets.
## Output includes sampled PNGs for ffmpeg and a contact strip for visual review.

const PROFILE := "res://Game/Characters/WhiteSailor/appearance.json"
const ACTIONS := ["run", "fall", "climb", "double_jump"]
const STEPS := 48
var surface: Node2D
var versions: Array[Dictionary] = []
var actors: Array[Dictionary] = []
var output := "res://tmp/white-sailor-continuity/capture"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var before := "res://tmp/white-sailor-continuity/before"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("before="):
			before = argument.trim_prefix("before=")
		elif argument.begins_with("output="):
			output = argument.trim_prefix("output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1120, 680)
	root.content_scale_size = root.size
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color("111b29"))
	surface = Node2D.new()
	root.add_child(surface)
	for directory in [before, PROFILE.get_base_dir()]:
		if not FileAccess.file_exists(directory.path_join("frame_manifest.json")):
			push_error("Missing comparison assets; supply before=<directory> containing the previous profile, manifest and Sheets.")
			quit(1)
			return
		var data := {
			"profile": JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("appearance.json"))),
			"manifest": JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("frame_manifest.json"))),
			"textures": {},
		}
		for sheet: String in data.profile.sheets:
			data.textures[sheet] = ImageTexture.create_from_image(Image.load_from_file(directory.path_join(data.profile.sheets[sheet].texture)))
		versions.append(data)
	_label("ANIMATION REGISTRATION / SAME ACTOR ORIGIN", Vector2(24, 12), 22)
	for row in 2:
		_label("BEFORE" if row == 0 else "AFTER", Vector2(24, 56 + row * 300), 17)
		for column in ACTIONS.size():
			var origin := Vector2(140 + column * 280, 330 + row * 300)
			_label(ACTIONS[column], Vector2(origin.x - 70, origin.y - 240), 18)
			var floor_line := Line2D.new()
			floor_line.points = PackedVector2Array([origin + Vector2(-110, 0), origin + Vector2(110, 0)])
			floor_line.default_color = Color("4a6074")
			floor_line.width = 1
			surface.add_child(floor_line)
			var center := Line2D.new()
			center.points = PackedVector2Array([origin + Vector2(0, -215), origin + Vector2(0, 8)])
			center.default_color = Color("263c4d")
			center.width = 1
			surface.add_child(center)
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.scale = Vector2.ONE * 0.82
			surface.add_child(sprite)
			actors.append({"sprite": sprite, "origin": origin, "version": row, "clip": ACTIONS[column]})
	var strip := Image.create(1120, 680 * 4, false, Image.FORMAT_RGBA8)
	for step in STEPS:
		for actor: Dictionary in actors:
			_sample(actor, float(step) / STEPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		assert(capture.save_png(output.path_join("frame_%03d.png" % step)) == OK)
		if step % (STEPS / 4) == 0:
			strip.blit_rect(capture, Rect2i(Vector2i.ZERO, capture.get_size()), Vector2i(0, step / (STEPS / 4) * 680))
	assert(strip.save_png(output.path_join("contact_strip.png")) == OK)
	print("CONTINUITY_CAPTURE_PASS steps=", STEPS)
	quit()


func _sample(actor: Dictionary, phase: float) -> void:
	var data: Dictionary = versions[actor.version]
	var sequence: Dictionary = data.profile.sequences[data.profile.clips[actor.clip].sequence]
	var index := mini(int(phase * sequence.cells.size()), sequence.cells.size() - 1)
	var info: Dictionary = data.manifest.frames[sequence.sheet][int(sequence.cells[index])]
	var texture := AtlasTexture.new()
	texture.atlas = data.textures[sequence.sheet]
	texture.region = Rect2(info.region[0], info.region[1], info.region[2], info.region[3])
	var sprite: Sprite2D = actor.sprite
	sprite.texture = texture
	sprite.position = actor.origin - Vector2(info[sequence.anchor][0], info[sequence.anchor][1]) * sprite.scale


func _label(text: String, position: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	surface.add_child(label)
