extends RefCounted
## A visual skin samples replacement drawings on the existing gameplay clock.
## Source clips remain intact: hit frames, sound events, loops and finished()
## continue to use the imported INARI timing even when the drawing count differs.

var profile: Dictionary = {}
var manifest: Dictionary = {}
var directory := ""
var textures: Dictionary = {}


func configure(path: String) -> void:
	# A sampler can be reused when switching skins. Neither old atlas entries
	# nor a replacement profile may survive a return to the source character.
	profile.clear()
	manifest.clear()
	textures.clear()
	directory = ""
	if path.is_empty():
		return
	directory = path.get_base_dir()
	profile = JSON.parse_string(FileAccess.get_file_as_string(path))
	manifest = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("frame_manifest.json")))
	assert(int(profile.version) == 1 and int(manifest.version) == 1, "Unsupported character asset format")
	assert(float(profile.display_scale) > 0.0, "Character display scale must be positive")


func sample(name: String, clip: Dictionary, time: float) -> Dictionary:
	assert(profile.clips.has(name), "Unmapped character action: " + name)
	var mapping: Dictionary = profile.clips[name]
	var sequence: Dictionary = profile.sequences[mapping.sequence]
	var phase := clampf(time / float(clip.length), 0.0, 1.0)
	var index := mini(floori(phase * sequence.cells.size()), sequence.cells.size() - 1)
	if mapping.has("frame_times"):
		# Optional normalized key times align a blade's contact drawing with the
		# game's hit frame, without shifting damage or input-buffer deadlines.
		index = 0
		for key_index in mapping.frame_times.size():
			if float(mapping.frame_times[key_index]) > phase:
				break
			index = key_index
	var cell := int(sequence.cells[index])
	var info: Dictionary = manifest.frames[sequence.sheet][cell]
	var cache_key := "%s:%d" % [sequence.sheet, cell]
	if not textures.has(cache_key):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(directory.path_join(profile.sheets[sequence.sheet].texture))
		atlas.region = Rect2(info.region[0], info.region[1], info.region[2], info.region[3])
		atlas.filter_clip = true
		textures[cache_key] = atlas
	var anchor: Array = info[sequence.anchor]
	return {
		"texture": textures[cache_key],
		"anchor": Vector2(anchor[0], anchor[1]),
		"attachment": sequence.anchor,
		"scale": float(profile.display_scale) * float(profile.sheets[sequence.sheet].get("scale", 1.0)),
		"sequence": mapping.sequence,
		"index": index,
	}
