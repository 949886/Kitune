extends SceneTree
## Actual event renders, source sound order, ownership and natural completion.

const AUDIO_ROOT := "res://Samples/ArtDirection/Original/INARI/Audio/"
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var lab: Node
var bow: Node
var audio: Node
var sequence: RefCounted
var events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func tick() -> void:
	sequence.step(1.0 / 60.0)
	bow.motion_animation.advance(1.0 / 60.0)


func until(state: String) -> void:
	for frame in 300:
		if sequence.state == state:
			return
		tick()
	assert(false, "Bow audio fixture did not reach " + state)


func verify_assets() -> void:
	var manifest: Dictionary = Assets.read_json(AUDIO_ROOT + "bow_events.json")
	assert(manifest.profile.object_id == 1873)
	assert(manifest.distance_volume == 1.0 and manifest.sample_rate == 48000)
	var sample_sets: Dictionary = {}
	for group: String in manifest.groups:
		sample_sets[group] = {}
		for filename: String in manifest.groups[group]:
			var info: Dictionary = manifest.renders[filename]
			assert(FileAccess.get_sha256(AUDIO_ROOT + filename) == info.sha256)
			var stream: AudioStreamWAV = load(AUDIO_ROOT + filename)
			assert(stream.stereo and stream.mix_rate == manifest.sample_rate)
			assert(stream.format == AudioStreamWAV.FORMAT_16_BITS)
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(stream.data)
			assert(
				hash.finish().hex_encode() == info.pcm_sha256, "Imported PCM must remain lossless"
			)
			assert(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)
			assert(absf(stream.get_length() - float(info.frames) / stream.mix_rate) < 0.0001)
			assert(info.one_shot and not info.samples.is_empty())
			assert(
				info.frames == info.playback_frames, "Output drain must not extend event lifetime"
			)
			for sample: String in info.samples:
				sample_sets[group][sample] = true
	# These are selected by the source GUID events, not inferred from filenames.
	assert(sample_sets.bow_pull.size() == 4 and sample_sets.bow_attack.size() == 4)
	assert(sample_sets.bow_death.size() == 3)
	assert(sample_sets.bow_shoot.keys() == ["Monster_Bow_Shoot"])
	assert(sample_sets.bow_attack.has("bowattack2"))


func run() -> void:
	verify_assets()
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	audio = lab.stage.audio
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	lab.player.set_physics_process(false)
	lab.player.position = bow.position + Vector2(240, 0)
	bow.motion_animation.set_process(false)
	sequence = bow.bow_attack
	audio.event_started.connect(
		func(group: String, handle: int): events.append({"group": group, "handle": handle})
	)
	sequence.begin(lab.player, 0)
	var pull := int(sequence.pull_sound)
	assert(events.size() == 1 and events.back().group == "bow_pull")
	assert(audio.is_event_playing(pull))
	sequence.cancel()
	assert(audio.is_event_playing(pull), "Native Ready cancellation does not return Pull")
	sequence.begin(lab.player, 1)
	assert(not audio.is_event_playing(pull))
	assert(events.back().group == "bow_attack")
	var melee := int(events.back().handle)
	for count in audio.voice_count * 2:
		audio.play("rifle_shot")
	assert(audio.is_event_playing(melee), "Ordinary pooled samples cannot steal owned events")
	audio.stop_event(pull)
	assert(audio.is_event_playing(melee), "An expired handle cannot stop a newer event")
	until("attack")
	assert(events.size() == 2, "Melee sound begins at Ready, not on the damage frame")
	until("idle")
	sequence.begin(lab.player, 0)
	until("attack")
	assert(events.size() == 4 and events.back().group == "bow_shoot")
	tick()
	assert(events.size() == 4, "A ranged attack starts its sound only once")
	var other_owner := Node.new()
	root.add_child(other_owner)
	var other_handle: int = audio.play_event("bow_pull", other_owner)
	bow.receive_study_hit({"Damage": 10000.0}, 1.0)
	assert(bow.dead and events[-2].group == "bow_death")
	assert(events.back().group == "enemy_common_death")
	var death_handle := int(events[-2].handle)
	assert(audio.is_event_playing(other_handle), "Death must only return this actor's sounds")
	for entry: Dictionary in audio.event_voices.values():
		if entry.owner_id == bow.get_instance_id():
			assert(entry.group in ["bow_death", "enemy_common_death"])
	assert(audio.is_event_playing(death_handle), "Hiding the dead bow must retain its death voice")
	var death_voice: WeakRef = weakref(audio.event_voices[death_handle].voice)
	# Audio playback advances on the audio clock, including in headless mode.
	# Bound this by wall time rather than relying on fixed-fps gameplay ticks.
	var deadline := Time.get_ticks_msec() + 5000
	while audio.is_event_playing(death_handle) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	assert(not audio.event_voices.has(death_handle), "Finished voices must release their handles")
	assert(death_voice.get_ref() == null, "Finished owned voices must free their nodes")
	audio.stop_events(other_owner)
	other_owner.queue_free()
	lab.queue_free()
	await process_frame
	print("BOW_AUDIO_PASS")
	quit()
