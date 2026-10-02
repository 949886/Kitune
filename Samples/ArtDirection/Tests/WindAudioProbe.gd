extends SceneTree
## Original FMOD PCM, spawn deferral, cooldown gating, kill attribution and voice ownership.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const AUDIO_ROOT := "res://Samples/ArtDirection/Original/INARI/Audio/"

var audio: Node
var starts: Array[Dictionary] = []
var stops: Array[int] = []


func _initialize() -> void:
	call_deferred("run")


func verify_assets() -> void:
	var manifest: Dictionary = Assets.read_json(AUDIO_ROOT + "wind_events.json")
	assert(manifest.groups.size() == 2 and manifest.renders.size() == 16)
	assert(manifest.source_sha256.has("StreamingAssets/SFX_Object.bank"))
	assert(manifest.source_sha256.has("MoveSpeedChangeTrigger.cs"))
	for filename: String in manifest.renders:
		var info: Dictionary = manifest.renders[filename]
		assert(FileAccess.get_sha256(AUDIO_ROOT + filename) == info.sha256)
		var stream: AudioStreamWAV = load(AUDIO_ROOT + filename)
		assert(stream.stereo and stream.mix_rate == manifest.sample_rate)
		assert(stream.format == AudioStreamWAV.FORMAT_16_BITS)
		assert(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(stream.data)
		assert(hash.finish().hex_encode() == info.pcm_sha256)
		assert(info.one_shot and info.distance_parameter and info.frames == info.playback_frames)
		assert(absf(stream.get_length() - float(info.frames) / manifest.sample_rate) < 0.0001)
		var suffix := "Object" if filename.begins_with("wind_buff_trigger") else "Player"
		assert(info.path == "event:/SFX/Object/WindBuff/WindBuff_" + suffix)
		assert(info.samples == ["WindBuff_" + suffix])


func record(group: String, handle: int) -> void:
	starts.append({"group": group, "handle": handle, "owner": audio.event_voices[handle].owner_id})


func run() -> void:
	verify_assets()
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	var victims: Dictionary = {}
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.set_physics_process(false)
		victims[enemy.data.kind] = enemy
	assert(victims.size() == 3, "Exercise all three native enemy subclasses")
	audio = lab.stage.audio
	audio.event_started.connect(record)
	audio.event_stopped.connect(func(_group: String, handle: int): stops.append(handle))
	var player: Node = lab.player
	var first: Node = lab.stage.wind_triggers[0]
	var second: Node = lab.stage.wind_triggers[1]
	player.wind_buff.reset()
	player.action_state = "spawn"
	first.enter(player)
	assert(player.wind_buff.level == 0 and first.pending_player != null)
	assert(starts.size() == 1 and starts[0].group == "wind_buff_trigger")
	assert(starts[0].owner == first.get_instance_id())
	assert(audio.is_event_playing(starts[0].handle))
	first.enter(player)
	assert(starts.size() == 1)
	player.action_state = "idle"
	first.advance(0.0)
	assert(player.wind_buff.level == 1 and starts.size() == 1)
	first.enter(player)
	assert(starts.size() == 1, "Cooldown blocks a repeated sound, as well as a repeated buff")
	second.enter(player)
	assert(starts.size() == 2 and starts[1].owner == second.get_instance_id())
	first.advance(float(first.source.cooldown) + 0.01)
	first.enter(player)
	assert(starts.size() == 3)
	var trigger_handle: int = starts.back().handle
	var level := 0
	var renewal_handle := 0
	for victim: Node in victims.values():
		player.wind_buff.reset()
		if level > 0:
			player.wind_buff.request(level)
		var old: int = audio.play_event("enemy_hit", victim)
		starts.clear()
		victim.receive_study_hit(
			{"Damage": victim.health, "kind": "weak_execution", "source_actor": player}, 1.0
		)
		assert(victim.dead and old in stops)
		var renewals := starts.filter(
			func(entry: Dictionary): return entry.group == "wind_buff_renewal"
		)
		assert(renewals.size() == 1 and renewals[0].owner == victim.get_instance_id())
		renewal_handle = int(renewals[0].handle)
		assert(
			audio.is_event_playing(renewal_handle),
			"Death cleanup must precede the new renewal event"
		)
		assert(player.wind_buff.level == (0 if level == 0 else 2))
		assert(
			audio.is_event_playing(trigger_handle), "Victim cleanup must leave station sounds alive"
		)
		if victim.data.kind == "EnemyBowMan":
			assert(starts[0].group == "bow_death")
			assert(starts[-1].group == "enemy_common_death")
		level += 1
	starts.clear()
	var non_player_kills := 0
	for victim: Node in lab.stage.enemies:
		if not victim.dead:
			non_player_kills += 1
			victim.receive_study_hit(
				{"Damage": victim.health, "kind": "weak_execution", "source_actor": victim}, 1.0
			)
	assert(non_player_kills > 0, "The source-attribution check must exercise an actual kill")
	assert(not starts.any(func(entry: Dictionary): return entry.group == "wind_buff_renewal"))
	var voice: WeakRef = weakref(audio.event_voices[renewal_handle].voice)
	var deadline := Time.get_ticks_msec() + 5000
	while audio.is_event_playing(renewal_handle) and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not audio.is_event_playing(renewal_handle))
	await process_frame
	assert(voice.get_ref() == null)
	var pending: int = audio.play_event("wind_buff_trigger", first)
	var pending_voice: WeakRef = weakref(audio.event_voices[pending].voice)
	lab.load_level(1)
	await process_frame
	assert(pending_voice.get_ref() == null)
	lab.queue_free()
	await process_frame
	print("WIND_AUDIO_PASS")
	quit()
