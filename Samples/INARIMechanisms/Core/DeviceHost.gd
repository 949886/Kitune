@tool
extends Node2D
## Minimal visual/event context for shared native mechanism code. No level,
## global player lookup, map coordinates, or hidden scene loads are involved.
const Location = preload("../PackageLocation.gd")
const Visual = preload("DeviceSprite.gd")
const TiledVisual = preload("DeviceTiledSprite.gd")
const SourceAnimation = preload("Native/Runtime/OriginalSceneAnimation.gd")
const Audio = preload("DeviceAudio.gd")
var visuals_by_go: Dictionary = {}
var visual_instances: Array[Node2D] = []
var animation: Node
var audio: Node
var document: Dictionary


func prepare(kind: String) -> Dictionary:
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/" + kind + "/"
	document = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	var records: Array = document.sprites.duplicate()
	records.sort_custom(
		func(a, b):
			return a.sort[0] < b.sort[0] or (a.sort[0] == b.sort[0] and a.sort[1] < b.sort[1])
	)
	for record: Dictionary in records:
		if record.sprite == null:
			continue
		var visual: Node2D = _make_visual(record)
		add_child(visual)
		visual.configure(record, document.sprite_info[record.sprite], folder)
		visual.sprite_library = document.sprite_info
		# Preserve relative source sorting without consuming global Z ranges.
		visual.z_index = visual_instances.size()
		visual_instances.append(visual)
		if record.has("go"):
			visuals_by_go[record.go] = visual
	if Engine.is_editor_hint():
		return document.record.duplicate(true)
	animation = SourceAnimation.new()
	add_child(animation)
	audio = Audio.new()
	audio.groups = document.audio
	audio.loop_frames = document.get("audio_loop_frames", {})
	audio.folder = folder
	add_child(audio)
	return document.record.duplicate(true)


func _make_visual(record: Dictionary) -> Node2D:
	return TiledVisual.new() if int(record.get("mode", 0)) != 0 else Visual.new()
