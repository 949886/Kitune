extends SceneTree
## Native bomb event mixes, animation crossings and death ownership/order.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const AUDIO_ROOT := "res://Samples/ArtDirection/Original/INARI/Audio/"

var lab: Node
var bomb: Node
var audio: Node
var combat: RefCounted
var events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func verify_assets() -> void:
	var manifest: Dictionary = Assets.read_json(AUDIO_ROOT + "bomb_events.json")
	assert(manifest.groups.size() == 5 and manifest.renders.size() == 40)
	var common: Dictionary = Assets.read_json(AUDIO_ROOT + "enemy_common_events.json")
	assert(common.renders.size() == 8)
	manifest.renders.merge(common.renders)
	assert(manifest.sample_rate == 48000 and manifest.distance_volume == 1.0)
	for filename: String in manifest.renders:
		var info: Dictionary = manifest.renders[filename]
		assert(FileAccess.get_sha256(AUDIO_ROOT + filename) == info.sha256)
		var stream: AudioStreamWAV = load(AUDIO_ROOT + filename)
		assert(stream.stereo and stream.mix_rate == 48000)
		assert(stream.format == AudioStreamWAV.FORMAT_16_BITS)
		assert(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(stream.data)
		assert(hash.finish().hex_encode() == info.pcm_sha256)
		assert(info.one_shot and info.frames == info.playback_frames)
		assert(absf(stream.get_length() - float(info.frames) / 48000.0) < 0.0001)
	var ready: Dictionary = manifest.renders[manifest.groups.bomb_ready[0]]
	var leg: Dictionary = manifest.renders[manifest.groups.bomb_ready_leg[0]]
	assert(ready.guid == leg.guid and ready.pcm_sha256 == leg.pcm_sha256)
	for filename: String in manifest.groups.bomb_chase:
		var samples: Array = manifest.renders[filename].samples
		assert(samples.size() == 2, "A chase event mixes spider and metal layers")
		assert(samples.any(func(name: String): return "Spider" in name))
		assert(samples.any(func(name: String): return "Metal" in name))


func at_time(seconds: float) -> void:
	bomb.motion_animation.tracks[0].time = seconds
	combat._play_chase_sound()


func run() -> void:
	verify_assets()
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.set_physics_process(false)
		if int(enemy.data.go) == 3277:
			bomb = enemy
	lab.player.set_physics_process(false)
	lab.player.position = bomb.position + Vector2(250, 0)
	bomb.motion_animation.set_process(false)
	combat = bomb.bomb_combat
	audio = lab.stage.audio
	audio.event_started.connect(
		func(group: String, handle: int):
			events.append({"kind": "start", "group": group, "handle": handle})
	)
	audio.event_stopped.connect(
		func(group: String, handle: int):
			events.append({"kind": "stop", "group": group, "handle": handle})
	)
	combat.target = lab.player
	combat._enter_route("chase", lab.player.position)
	assert(events.size() == 1 and events.back().group == "bomb_patrol_voice")
	assert(combat.settings.chase_sound_frames == [4.0, 11.0])
	var clip: Dictionary = bomb.motion_animation.tracks[0].clip
	var rate := float(clip.frame_rate)
	at_time(0.0)
	at_time(3.9 / rate)
	assert(events.size() == 1)
	at_time(4.1 / rate)
	assert(events.size() == 2 and events.back().group == "bomb_chase")
	combat._play_chase_sound()
	assert(events.size() == 2, "Duplicate callbacks in one update must not double a footstep")
	at_time(11.1 / rate)
	assert(events.size() == 3)
	at_time(0.0)
	at_time(4.1 / rate)
	assert(events.size() == 4, "The next animation loop must generate another footstep")
	# The native dictionary survives state changes and neither backfills a
	# loop's missed tail nor plays a first-call threshold with previous=1.
	combat.chase_sound.previous_normalized = 1.0
	at_time(11.1 / rate)
	assert(events.size() == 4)

	combat._start_fuse()
	assert(events[-2].group == "bomb_ready" and events[-1].group == "bomb_ready_leg")
	var first := int(events[-2].handle)
	var second := int(events[-1].handle)
	assert(first != second and audio.is_event_playing(first) and audio.is_event_playing(second))
	combat._cancel_fuse()
	assert(audio.is_event_playing(first) and audio.is_event_playing(second))
	combat._start_fuse()
	assert(events[-2].group == "bomb_ready" and events[-1].group == "bomb_ready_leg")
	var other := Node.new()
	root.add_child(other)
	var unrelated: int = audio.play_event("bow_pull", other)
	combat.explode()
	assert(bomb.dead and events.back().group == "bomb_explosion" and events.back().kind == "start")
	assert(not events.any(func(entry: Dictionary): return entry.group == "enemy_common_death"))
	assert(not audio.is_event_playing(first) and not audio.is_event_playing(second))
	assert(audio.is_event_playing(unrelated))
	var explosion := int(events.back().handle)
	for entry: Dictionary in audio.event_voices.values():
		if entry.owner_id == bomb.get_instance_id():
			assert(entry.group == "bomb_explosion")
	assert(audio.is_event_playing(explosion))
	var voice: WeakRef = weakref(audio.event_voices[explosion].voice)
	var deadline := Time.get_ticks_msec() + 5000
	while audio.is_event_playing(explosion) and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not audio.is_event_playing(explosion))
	await process_frame
	assert(voice.get_ref() == null)
	# A normal kill returns preparation voices without inventing a blast sound.
	for enemy: Node in lab.stage.enemies:
		if int(enemy.data.go) == 3278:
			enemy.bomb_combat._start_fuse()
			var ready_handle := int(events.back().handle)
			enemy.receive_study_hit({"Damage": 100.0}, 1.0)
			assert(enemy.dead and not audio.is_event_playing(ready_handle))
			assert(events.back().group == "enemy_common_death" and events.back().kind == "start")
			assert(audio.is_event_playing(int(events.back().handle)))
	var explosion_starts := 0
	for entry: Dictionary in events:
		if entry.kind == "start" and entry.group == "bomb_explosion":
			explosion_starts += 1
	assert(explosion_starts == 1)
	other.queue_free()
	lab.queue_free()
	await process_frame
	print("BOMB_AUDIO_PASS")
	quit()
