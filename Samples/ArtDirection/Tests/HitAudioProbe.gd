extends SceneTree
## Native event mixes, victim stack selection, heavy-hit reset and death ordering.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const AUDIO_ROOT := "res://Samples/ArtDirection/Original/INARI/Audio/"

var starts: Array[Dictionary] = []
var stops: Array[int] = []
var audio: Node


func _initialize() -> void:
	call_deferred("run")


func verify_assets() -> void:
	var manifest: Dictionary = Assets.read_json(AUDIO_ROOT + "enemy_hit_events.json")
	assert(manifest.groups.size() == 4 and manifest.renders.size() == 32)
	assert(manifest.source_sha256.has("StreamingAssets/SFX_Player.bank"))
	for group: String in manifest.groups:
		for filename: String in manifest.groups[group]:
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
			assert(info.one_shot and info.frames == info.playback_frames)
			assert(absf(stream.get_length() - float(info.frames) / manifest.sample_rate) < 0.0001)
			assert(info.distance_parameter == (group == "enemy_hit"))
			# These are layered FMOD events, not a guessed single WAV sample.
			assert(info.samples.size() >= 2)
			if group.begins_with("enemy_stack_hit_"):
				assert(info.path.ends_with("Player_Shuriken_StackHit_" + group.right(1)))


func record(group: String, handle: int) -> void:
	var owner_id: int = audio.event_voices[handle].owner_id
	var owner_node: Node = instance_from_id(owner_id)
	var stacks := int(owner_node.kunai.weak_points) if "kunai" in owner_node else -1
	starts.append({"group": group, "handle": handle, "stacks": stacks, "owner": owner_id})


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
	audio = lab.stage.audio
	audio.event_started.connect(record)
	audio.event_stopped.connect(func(_group: String, handle: int): stops.append(handle))
	var rifle: Node = victims.EnemyRifleMan
	for stacks in [1, 2, 3]:
		starts.clear()
		rifle.kunai.weak_points = stacks
		var health: float = rifle.health
		# Secondary damage packets can carry index zero while this victim still
		# has stacks. The source OnDamaged branch reads the victim, not the packet.
		rifle.receive_study_hit(
			{"Damage": 0.0, "kind": "weak_execution", "weak_point_index": 0}, 1.0
		)
		assert(starts.size() == 1 and starts[0].group == "enemy_stack_hit_%d" % stacks)
		assert(starts[0].stacks == stacks and starts[0].owner == rifle.get_instance_id())
		assert(rifle.kunai.weak_points == 0 and rifle.health == health)
		assert(audio.is_event_playing(starts[0].handle))
		audio.stop_events(rifle)
	starts.clear()
	rifle.receive_study_hit({"Damage": 0.0, "kind": "weak_execution"}, 1.0)
	assert(starts.is_empty(), "An unmarked victim must not invent a StackHit")
	rifle.kunai.weak_points = 2
	for kind in ["kunai_stuck", "kunai_dash"]:
		rifle.receive_study_hit({"Damage": 0.0, "kind": kind}, 1.0)
	assert(starts.is_empty() and rifle.kunai.weak_points == 2)
	rifle.receive_study_hit({"Damage": 0.0, "interaction": 8}, 1.0)
	assert(starts.size() == 2)
	assert(starts[0].group == "enemy_stack_hit_2" and starts[1].group == "enemy_hit")
	assert(rifle.kunai.weak_points == 0)
	starts.clear()
	rifle.kunai.weak_points = 1
	rifle.receive_study_hit({"Damage": 0.0, "interaction": 4}, 1.0)
	assert(starts.is_empty() and rifle.kunai.weak_points == 1)
	victims.EnemyBowMan.receive_study_hit({"Damage": 0.0, "interaction": 4}, 1.0)
	assert(starts.size() == 1 and starts[0].group == "enemy_hit")
	# All three shipped subclasses return attached sounds on death, despite
	# OnDamaged calling Borrow(..., stoppable:false); that argument is unused.
	var unrelated: int = audio.play_event("enemy_stack_hit_3", lab.player)
	for victim: Node in victims.values():
		starts.clear()
		victim.kunai.weak_points = 3
		victim.receive_study_hit({"Damage": victim.health, "kind": "weak_execution"}, 1.0)
		assert(victim.dead and starts[0].group == "enemy_stack_hit_3")
		assert(starts[0].handle in stops and not audio.is_event_playing(starts[0].handle))
		assert(audio.is_event_playing(unrelated))
	var voice: WeakRef = weakref(audio.event_voices[unrelated].voice)
	var deadline := Time.get_ticks_msec() + 5000
	while audio.is_event_playing(unrelated) and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not audio.is_event_playing(unrelated))
	await process_frame
	assert(voice.get_ref() == null)
	var pending: int = audio.play_event("enemy_stack_hit_3", lab.player)
	var pending_voice: WeakRef = weakref(audio.event_voices[pending].voice)
	lab.load_level(1)
	await process_frame
	assert(pending_voice.get_ref() == null)
	lab.queue_free()
	await process_frame
	print("HIT_AUDIO_PASS")
	quit()
