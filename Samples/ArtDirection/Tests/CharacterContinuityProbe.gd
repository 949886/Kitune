extends SceneTree
## Temporal visual regression: inspect the actual exported face pixels, not just
## pivot metadata. A stable actor can still jitter if its drawing moves inside
## the frame, so pixel centroid and area are checked across the looping poses.

const DIRECTORY := "res://Game/Characters/WhiteSailor"
var failures: Array[String] = []


func _initialize() -> void:
	var directory := DIRECTORY
	var legacy := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("legacy="):
			directory = argument.trim_prefix("legacy=")
			legacy = true
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("appearance.json")))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("frame_manifest.json")))
	var source_marks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join("Source/registration.json")))
	var report := {}
	for name in ["idle", "run", "fall"]:
		var sequence: Dictionary = profile.sequences[profile.clips[name].sequence]
		var samples: Array[Dictionary] = []
		var smallest := INF
		var largest := 0.0
		var max_step := 0.0
		for cell in sequence.cells:
			var info: Dictionary = manifest.frames[sequence.sheet][int(cell)]
			var image: Image
			var head_axis: Array
			if legacy:
				# The old compiler centered the source cell on x=128 and rooted
				# y on the silhouette bottom. Reconstruct only a head search window;
				# measured centroids still come from the old rendered PNG pixels.
				var sheet := Image.load_from_file(directory.path_join(profile.sheets[sequence.sheet].texture))
				image = sheet.get_region(Rect2i(info.region[0], info.region[1], info.region[2], info.region[3]))
				var marks: Dictionary = source_marks.sheets[sequence.sheet][int(cell)]
				for point: Array in marks.head_axis:
					head_axis.append([float(info.feet[0]) + float(point[0]) - float(profile.cell_size[0]) / 2.0, float(info.feet[1]) + float(point[1]) - float(marks.support[1])])
			else:
				image = Image.load_from_file(directory.path_join(info.path))
				head_axis = info.registration.head_axis
			var sample := _face_pixels(image, head_axis)
			sample.center -= Vector2(info.feet[0], info.feet[1])
			_check(sample.count > 80, "Face pixel sample too small: %s/%d" % [name, cell])
			samples.append(sample)
			smallest = minf(smallest, sample.count)
			largest = maxf(largest, sample.count)
		# Include the last -> first boundary: this caught the old fall loop.
		for index in samples.size():
			var next: Dictionary = samples[(index + 1) % samples.size()]
			max_step = maxf(max_step, samples[index].center.distance_to(next.center))
		var ratio := largest / maxf(1.0, smallest)
		report[name] = {"max_face_step_pixels": max_step, "face_area_ratio": ratio}
		_check(max_step < 12.0, "Loop face jumps more than 3 world pixels: " + name)
		_check(ratio < 1.5, "Loop face changes size: " + name)
	# All airborne poses keep an anatomical body pivot. A rotating head or
	# changing silhouette height may move legitimately; the pelvis must not.
	for sheet: String in manifest.frames:
		for info: Dictionary in manifest.frames[sheet]:
			if not legacy and info.registration.mode == "air":
				_check(absf(float(info.registration.pelvis[0]) - float(info.feet[0])) < 0.001, "Air body centered independently of hair/weapon: " + info.path)
	# Action semantics: a held wall grip is not a repeated climbing step, and
	# starting to run must not play the complete crouch/jump/flight sequence.
	_check(profile.clips.run_ready.sequence != profile.clips.jump.sequence, "Run startup must not use jump poses")
	_check(profile.sequences[profile.clips.climb.sequence].cells.size() == 1, "Stationary wall grip remains stable")
	DirAccess.make_dir_recursive_absolute("res://tmp/white-sailor-continuity")
	var report_path := "res://tmp/white-sailor-continuity/pixel_metrics%s.json" % ("_before" if legacy else "")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("CONTINUITY_PIXEL_METRICS ", JSON.stringify(report))
	if failures.is_empty():
		print("CHARACTER_CONTINUITY_PASS")
	quit(0 if failures.is_empty() else 1)


func _face_pixels(image: Image, axis: Array) -> Dictionary:
	var crown := Vector2(axis[0][0], axis[0][1])
	var chin := Vector2(axis[1][0], axis[1][1])
	var bounds := Rect2i(Vector2i(crown.min(chin) - Vector2(22, 0)), Vector2i((crown - chin).abs() + Vector2(44, 4)))
	bounds = bounds.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum := Vector2.ZERO
	var count := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var color := image.get_pixel(x, y)
			# Pink/peach face pixels; exclude white hair, dark outlines and alpha.
			if color.a > 0.5 and color.r > 0.65 and color.r - color.g > 0.09 and color.g > 0.30 and color.b > color.g * 0.75:
				sum += Vector2(x, y)
				count += 1
	return {"count": count, "center": sum / maxf(1.0, count)}


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)
