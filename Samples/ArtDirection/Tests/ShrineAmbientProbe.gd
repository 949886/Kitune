extends SceneTree
## Verify native Timeline bindings, conversation shot, float clock and reflected frames.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Stage = preload("res://Samples/ArtDirection/Runtime/OriginalStage.gd")
const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")
const Animator = preload("res://Samples/ArtDirection/Runtime/InariAnimation.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source: Dictionary = Assets.read_json(Assets.ROOT + "shrine_ambient.json")
	assert(source.tracks.size() == 6 and source.poses.size() == 5)
	var profiles: Array = Assets.read_json("res://Samples/ArtDirection/Profiles/levels.json")
	var profile: Dictionary
	for item: Dictionary in profiles:
		if item.get("ambient_animation", "") == "shrine_ambient.json":
			profile = item
	assert(not profile.is_empty())
	var stage := Stage.new()
	root.add_child(stage)
	stage.configure(Assets.ROOT + profile.scene_data, profile)
	stage.animation.set_process(false)
	assert(stage.animation.tracks.size() == stage.data.animations.size() + 1)
	var ambient: Array[Dictionary] = []
	for track: Dictionary in stage.animation.tracks:
		if track.clip.get("clock", "") == "timeline_loop":
			ambient.append(track)
			assert(track.clip.frames.size() == (16 if track.clip.name == "BowIdle" else 28))
			assert(track.clip.frame_rate == 24)
			assert(track.node.current_sprite == track.clip.frames[0][1])
	assert(ambient.size() == 6)
	_verify_kurori(stage, source)
	_verify_scenery(stage, source)
	# The native coroutine samples before incrementing and never resets its float clock.
	var elapsed: float = 0.0
	for tick in 3600:
		var expected := maxi(0, floori(_float32(elapsed * 24.0)))
		stage.animation.advance(1.0 / 60.0)
		for track: Dictionary in ambient:
			assert(
				(
					track.node.current_sprite
					== track.clip.frames[expected % track.clip.frames.size()][1]
				)
			)
		elapsed = _float32(elapsed + _float32(1.0 / 60.0))
	assert(ambient[0].time == elapsed and elapsed > 59.0)
	for key: String in source.new_frames:
		var info := Assets.sprite_info(key)
		var native := Image.new()
		assert(native.load(Assets.ROOT + info.path) == OK)
		native.convert(Image.FORMAT_RGBA8)
		var imported := (load(Assets.ROOT + info.path) as Texture2D).get_image()
		if imported.is_compressed():
			imported.decompress()
		imported.convert(Image.FORMAT_RGBA8)
		assert(native.get_data() == imported.get_data(), "Changed native pixels: " + key)
	stage.queue_free()
	await process_frame
	# Exercise the actual profile, including the separately rendered water scene.
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(profiles.find(profile))
	assert(lab.player.facing == -1.0)
	var source_root: Vector2 = lab.player.position + lab.player.body_shape.position
	assert(source_root.distance_to(Vector2(2.72, -103.2)) < 0.001)
	for frame in 90:
		await physics_frame
	await process_frame
	# SceneTree.process_frame precedes the nodes' process callbacks. Inspect the
	# reflected frame after the capture's priority-450 synchronization has run.
	await create_timer(0.0).timeout
	assert(lab.camera_rig.source.virtual_camera == source.camera.virtual_camera)
	assert(lab.camera_rig.target.name == "ShotPoint" and lab.camera_rig.target != lab.player)
	assert(lab.camera_rig.camera_2d.position.distance_to(Vector2(0, -184)) < 0.001)
	assert(is_equal_approx(lab.stage.projection.distance, source.camera.distance))
	assert(source.player_idle.frames.size() == 13 and source.player_idle.frame_rate == 20)
	assert(lab.player.sprite.clip_name == "BackIDLE")
	assert(lab.player.sprite.scale.x == -1.0)
	assert(lab.water_capture.actor_pairs[0].copy.texture == lab.player.sprite.texture)
	for pose: Dictionary in source.poses:
		if not lab.stage.visuals_by_go.has(pose.go):
			# The profile omits the opening Black overlay after its transition.
			assert(int(pose.go) == 25)
			continue
		var main: Node = lab.stage.visuals_by_go[pose.go]
		var matched := false
		for pair: Dictionary in lab.water_capture.stage_pairs:
			if pair.source == main:
				assert(pair.copy.modulate == main.modulate)
				assert(pair.copy.transform == main.transform)
				matched = true
		assert(matched, "Every rendered excerpt pose must reach the reflection")
	for clip: Dictionary in source.tracks:
		var main: Node = lab.stage.visuals_by_go[clip.go]
		var copy: Node
		for pair: Dictionary in lab.water_capture.stage_pairs:
			if pair.source == main:
				copy = pair.copy
		assert(is_instance_valid(copy))
		assert(main.current_sprite == copy.current_sprite)
		var prefix := (
			"Sprite_Shaman_BowIdle_" if clip.name == "BowIdle" else "Sprite_ShamanLeader_Idle_"
		)
		assert(str(Assets.sprite_info(main.current_sprite).name).begins_with(prefix))
		assert(main.data.flip == copy.data.flip and main.modulate == copy.modulate)
		assert(main.z_index == copy.z_index)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		assert(Capture.save_png(root, "res://tmp/art-direction/shrine-ambient.png") == OK)
	await _verify_player_idle(lab, source.player_idle)
	lab.queue_free()
	await process_frame
	print("SHRINE_AMBIENT_PASS")
	quit()


func _verify_player_idle(lab: Node, clip: Dictionary) -> void:
	var animation := Animator.new()
	root.add_child(animation)
	animation.clips[clip.name] = clip
	animation.play(clip.name)
	var elapsed := 0.0
	for tick in 3600:
		var index := floori(_float32(elapsed * 20.0)) % 13
		animation.advance(1.0 / 60.0)
		assert(animation.texture == Assets.texture(clip.frames[index][1]))
		elapsed = _float32(elapsed + _float32(1.0 / 60.0))
	assert(animation.elapsed == elapsed)
	animation.queue_free()
	# A real movement input leaves the excerpt without delaying the controller.
	Input.action_press(lab.player.input_action("right"))
	await physics_frame
	await physics_frame
	assert(lab.player.idle_clip == "idle" and lab.player.velocity.x > 0.0)
	assert(lab.player.sprite.clip_name == "run")
	Input.action_release(lab.player.input_action("right"))
	for frame in 90:
		await physics_frame
	assert(lab.player.sprite.clip_name == "idle")
	# Combat and reset also leave the introduction instead of returning to it.
	lab.player.idle_clip = clip.name
	var event := InputEventAction.new()
	event.action = lab.player.input_action("heavy_attack")
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	await physics_frame
	assert(lab.player.idle_clip == "idle" and lab.player.sprite.clip_name == "heavy_attack")
	Input.action_release(event.action)
	lab.player.idle_clip = clip.name
	lab.player.respawn()
	assert(lab.player.idle_clip == "idle")


func _verify_kurori(stage: Node, source: Dictionary) -> void:
	var pose: Dictionary = source.poses[0]
	var npc: Node2D = stage.visuals_by_go[pose.go]
	assert(npc.position.distance_to(Vector2(-93.28, -112.496)) < 0.001)
	assert(npc.modulate == Color.WHITE and npc.data.flip == [false, false])
	assert(int(npc.data.sort[0]) == 4 and int(npc.data.sort[1]) == 2)
	assert(npc.z_index == stage.sort_depth(pose.sort))
	assert(is_equal_approx(source.pose_evidence[0].sample_time, 83.825))
	# The visual excerpt must not overwrite the underlying scene's hidden initial state.
	for item: Dictionary in stage.data.sprites:
		if item.go == pose.go:
			assert(Assets.color(item.color) == Color(0, 0, 0, 0) and item.flip[0])
			assert(
				(
					Assets.vec(item.transform.slice(4, 6)).distance_to(Vector2(683.36, -112.496))
					< 0.001
				)
			)
			return
	assert(false, "Missing serialized Kurori renderer")


func _verify_scenery(stage: Node, source: Dictionary) -> void:
	assert(source.scene_pose_evidence.size() == 4)
	var fog: Node = stage.visuals_by_go[22.0]
	assert(is_equal_approx(fog.modulate.a, 0.4))
	var soul: Node = stage.visuals_by_go[57.0]
	assert(soul.modulate.is_equal_approx(Color(0.39, 0.39, 0.39, 1.0)))
	assert(stage.visuals_by_go[47.0].modulate.a == 0.0)
	for proof: Dictionary in source.scene_pose_evidence:
		assert(is_equal_approx(proof.sample_time, 83.825))
		if int(proof.go) in [47, 57]:
			assert(proof.pre_hold and proof.clip_time == 0.0)
		if int(proof.go) == 22:
			assert(not proof.pre_hold and proof.clip_time == 4.0)
	# Source scene data remains available separately from the sampled Timeline.
	for original: Dictionary in stage.data.sprites:
		if int(original.go) == 22:
			assert(is_equal_approx(original.color[3], 0.2823529541492462))


func _float32(value: float) -> float:
	return PackedFloat32Array([value])[0]
