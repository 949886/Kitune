extends Node
## Default Animator states and SimpleAnimator caches, using original frame times.

const PIXELS_PER_UNIT := 16.0

var tracks: Array[Dictionary] = []


func release_visuals(ids: Array) -> void:
	tracks = tracks.filter(func(track: Dictionary): return track.clip.go not in ids)


func configure(source_tracks: Array, visuals: Dictionary) -> void:
	for clip: Dictionary in source_tracks:
		if not visuals.has(clip.go):
			continue

		var track := {"clip": clip, "node": visuals[clip.go], "time": 0.0, "finished": false}
		tracks.append(track)
		_apply(track)


func replace_sprite_tracks(source_tracks: Array, visuals: Dictionary) -> void:
	var ids := source_tracks.map(func(clip: Dictionary): return clip.go)
	tracks = tracks.filter(
		func(track: Dictionary): return track.clip.kind != "sprite" or track.clip.go not in ids
	)
	configure(source_tracks, visuals)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	for track: Dictionary in tracks:
		if track.finished:
			continue

		_apply(track)
		var clip: Dictionary = track.clip
		var step := delta * float(track.node.get_meta("source_animation_scale", 1.0))
		if clip.get("clock", "") == "timeline_loop":
			# SpriteTrackMixerBehaviour.LoopCoroutine keeps an unwrapped C# float clock.
			track.time = _float32(float(track.time) + _float32(delta))
			continue
		if clip.reset_on_loop:
			# The cached player uses C# float arithmetic, including at loop boundaries.
			track.time = _float32(float(track.time) + _float32(_float32(step) * float(clip.speed)))
		else:
			track.time += step * float(clip.speed)
		if track.time < float(clip.length):
			continue

		if clip.loop:
			# SimpleAnimator discards the overshoot; Unity Animator keeps it.
			track.time = (
				0.0 if clip.reset_on_loop else fposmod(float(track.time), float(clip.length))
			)
		else:
			track.time = float(clip.length)
			track.finished = true
			_apply(track)


func _apply(track: Dictionary) -> void:
	var clip: Dictionary = track.clip
	var time := float(track.time)
	if clip.kind in ["sprite", "material"]:
		var sprite = clip.frames[0][1]
		if clip.get("clock", "") == "timeline_loop":
			var index := maxi(0, floori(_float32(time * float(clip.frame_rate))))
			sprite = clip.frames[index % clip.frames.size()][1]
		elif clip.reset_on_loop:
			var index := floori(_float32(time * float(clip.frame_rate)))
			sprite = clip.frames[mini(index, clip.frames.size() - 1)][1]
		else:
			for frame: Array in clip.frames:
				if float(frame[0]) > time:
					break
				sprite = frame[1]
		if clip.kind == "sprite":
			track.node.set_animation_sprite(sprite)
		else:
			track.node.set_animation_material(sprite)
	elif clip.kind == "active":
		track.node.set_animation_visibility(_sample(clip.keys, time) >= 0.5)
	elif clip.kind == "position":
		var offset := (
			Vector2(
				_sample(clip.axes[0], time, clip.initial[0]) - float(clip.initial[0]),
				-(_sample(clip.axes[1], time, clip.initial[1]) - float(clip.initial[1]))
			)
			* PIXELS_PER_UNIT
		)
		var basis: Array = clip.parent_basis
		track.node.set_animation_offset(
			Vector2(basis[0], basis[1]) * offset.x + Vector2(basis[2], basis[3]) * offset.y
		)
	elif clip.kind == "rotation":
		var angle := _sample(clip.keys, time)
		track.node.set_animation_rotation(-deg_to_rad(angle - float(clip.initial_angle)))


func _sample(keys: Array, time: float, fallback := 0.0) -> float:
	if keys.is_empty():
		return fallback
	var key: Array = keys[0]
	for candidate: Array in keys:
		if float(candidate[0]) > time:
			break
		key = candidate
	# Unity stores cubic coefficients relative to each streamed key's time.
	var t := maxf(0.0, time - float(key[0]))
	var coefficients: Array = key[1]
	return (
		((float(coefficients[0]) * t + float(coefficients[1])) * t + float(coefficients[2])) * t
		+ float(coefficients[3])
	)


func _float32(value: float) -> float:
	return PackedFloat32Array([value])[0]
