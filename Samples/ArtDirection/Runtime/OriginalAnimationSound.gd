extends RefCounted
## FmodSfxPool.PlayLoopSound's per-actor normalized-time crossing rule.

var previous_normalized := 1.0


func step(actor: Node, frames: Array, group: String) -> void:
	if actor.motion_animation.tracks.is_empty():
		return
	var track: Dictionary = actor.motion_animation.tracks[0]
	var clip: Dictionary = track.clip
	var frame_count := roundi(float(clip.frame_rate) * float(clip.length))
	if frame_count <= 0:
		return
	var normalized := fposmod(float(track.time) / float(clip.length), 1.0)
	for frame: float in frames:
		var threshold := frame / float(frame_count)
		if previous_normalized < threshold and normalized >= threshold:
			actor.get_parent().audio.play_event(group, actor)
	# The source stores a single value per transform, not per animation. A
	# repeated call in the same update cannot duplicate sounds. At a wrap it
	# does not reconstruct missed crossings from the tail of the prior loop.
	previous_normalized = normalized
