extends Node
## Local event samples only. The host does not need the original FMOD manager.
signal event_played(event: String)
var groups: Dictionary = {}
var folder := ""
var next_variant: Dictionary = {}
var loop_frames: Dictionary = {}


func play(event: String) -> void:
	play_event(event)


func play_event(event: String, owner_node: Node = null) -> void:
	if not groups.has(event):
		return
	var files: Array = groups[event]
	var index: int = next_variant.get(event, 0)
	next_variant[event] = (index + 1) % files.size()
	var voice := AudioStreamPlayer.new()
	add_child(voice)
	voice.stream = load(folder + files[index])
	voice.set_meta(
		"event_owner", owner_node.get_instance_id() if is_instance_valid(owner_node) else 0
	)
	if loop_frames.has(files[index]):
		# Duplicate the stream so the import/resource cache remains immutable.
		var stream: AudioStreamWAV = voice.stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(loop_frames[files[index]])
		voice.stream = stream
	voice.finished.connect(voice.queue_free)
	voice.play()
	event_played.emit(event)


func stop_events(owner_node: Node) -> void:
	var owner_id := owner_node.get_instance_id() if is_instance_valid(owner_node) else 0
	for voice: AudioStreamPlayer in get_children():
		if voice.get_meta("event_owner") == owner_id:
			voice.stop()
			voice.queue_free()
