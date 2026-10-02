extends Node
## Original samples and offline FMOD event mixes; live spatial processing is pending.

signal event_started(group: String, handle: int)
signal event_stopped(group: String, handle: int)

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const AUDIO_ROOT := "res://Samples/ArtDirection/Original/INARI/Audio/"

@export var volume_db := 0.0
@export var voice_count := 8

var groups: Dictionary
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var last_selection: Dictionary = {}
var event_voices: Dictionary = {}
var next_event_handle := 1
var timeline_loops: Dictionary = {}


func _ready() -> void:
	groups = Assets.read_json(AUDIO_ROOT + "sounds.json").groups
	groups.merge(Assets.read_json(AUDIO_ROOT + "bow_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "bomb_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "enemy_common_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "enemy_hit_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "wind_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "machinery_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "battle_events.json").groups)
	groups.merge(Assets.read_json(AUDIO_ROOT + "battle_bow_events.json").groups)
	var timer_audio: Dictionary = Assets.read_json(AUDIO_ROOT + "timer_events.json")
	groups.merge(timer_audio.groups)
	for filename: String in timer_audio.renders:
		if not timer_audio.renders[filename].one_shot:
			timeline_loops[filename] = int(timer_audio.renders[filename].timeline_loop_frames)
	var ice_audio: Dictionary = Assets.read_json(AUDIO_ROOT + "ice_events.json")
	groups.merge(ice_audio.groups)
	for filename: String in ice_audio.renders:
		if not ice_audio.renders[filename].one_shot:
			timeline_loops[filename] = int(ice_audio.renders[filename].timeline_loop_frames)
	var elevator_audio: Dictionary = Assets.read_json(AUDIO_ROOT + "elevator_events.json")
	groups.merge(elevator_audio.groups)
	for filename: String in elevator_audio.renders:
		var record: Dictionary = elevator_audio.renders[filename]
		if not record.one_shot:
			timeline_loops[filename] = int(record.timeline_loop_frames)
	for index in voice_count:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = volume_db
		add_child(voice)
		voices.append(voice)


func play(group: String) -> void:
	var stream := _choose_stream(group)
	if stream == null:
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = stream
	voice.play()


func play_event(group: String, owner_node: Node) -> int:
	var stream := _choose_stream(group)
	if stream == null:
		return 0
	# An event has an independent lifetime. Ordinary footsteps and rifle shots
	# must not steal a bow voice or invalidate a handle through pool reuse.
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	add_child(voice)
	var handle := next_event_handle
	next_event_handle += 1
	event_voices[handle] = {
		"voice": voice, "group": group, "owner_id": owner_node.get_instance_id()
	}
	voice.finished.connect(stop_event.bind(handle))
	voice.play()
	event_started.emit(group, handle)
	return handle


func stop_event(handle: int) -> void:
	if not event_voices.has(handle):
		return
	var entry: Dictionary = event_voices[handle]
	event_voices.erase(handle)
	entry.voice.stop()
	entry.voice.queue_free()
	event_stopped.emit(entry.group, handle)


func stop_events(owner_node: Node) -> void:
	for handle: int in event_voices.keys():
		if event_voices[handle].owner_id == owner_node.get_instance_id():
			stop_event(handle)


func is_event_playing(handle: int) -> bool:
	return event_voices.has(handle) and event_voices[handle].voice.playing


func _choose_stream(group: String) -> AudioStream:
	var samples: Array = groups.get(group, [])
	if samples.is_empty():
		return null

	var index := randi_range(0, samples.size() - 1)
	if samples.size() > 1 and index == int(last_selection.get(group, -1)):
		index = (index + 1) % samples.size()
	last_selection[group] = index

	var filename: String = samples[index]
	if not streams.has(filename):
		streams[filename] = load(AUDIO_ROOT + filename)
		if timeline_loops.has(filename):
			var loop: AudioStreamWAV = streams[filename].duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(timeline_loops[filename])
			streams[filename] = loop
	return streams[filename]
