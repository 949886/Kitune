extends SceneTree
## Replacement artwork must cover every source action and preserve the controller
## contract. Exercise real actors, imported alpha textures, pivots and hit timing.

const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const PROFILE := "res://Game/Characters/WhiteSailor/appearance.json"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)


func run() -> void:
	var original := Player.new()
	var player := Player.new()
	player.appearance_path = PROFILE
	root.add_child(original)
	root.add_child(player)
	original.set_physics_process(false)
	player.set_physics_process(false)
	check(player.body_size == original.body_size, "Skin must not change collision dimensions")
	check(player.sprite.clips == original.sprite.clips, "All original gameplay clocks must be preserved")
	var profile: Dictionary = player.sprite.appearance.profile
	var manifest: Dictionary = player.sprite.appearance.manifest
	var verified_frames := 0
	var expected_frames := 0
	for sheet: String in profile.sheets:
		var grid: Array = profile.sheets[sheet].get("grid", profile.grid)
		expected_frames += int(grid[0]) * int(grid[1])
		var path := PROFILE.get_base_dir().path_join(profile.sheets[sheet].texture)
		var texture := load(path) as Texture2D
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		check(image.detect_alpha() != Image.ALPHA_NONE, "Atlas must have real alpha: " + sheet)
		check(image.get_pixel(0, 0).a == 0.0, "No opaque checkerboard / key background: " + sheet)
		for info: Dictionary in manifest.frames[sheet]:
			var region := Rect2i(info.region[0], info.region[1], info.region[2], info.region[3])
			var frame := image.get_region(region)
			var bounds := frame.get_used_rect()
			check(bounds.has_area(), "Every packed frame contains artwork")
			check(bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < region.size.x and bounds.end.y < region.size.y, "Transparent gutter around each complete silhouette")
			verified_frames += 1
	check(verified_frames == expected_frames, "All declared source cells must be exported")
	var source_clips: Dictionary = original.sprite.clips
	for name: String in source_clips:
		check(profile.clips.has(name), "Missing action mapping: " + name)
		var clip: Dictionary = source_clips[name]
		player.sprite.play(name, true)
		original.sprite.play(name, true)
		for progress in [0.0, 0.11, 0.49, 0.76, 1.1]:
			var elapsed: float = float(clip.length) * progress
			player.sprite.elapsed = elapsed
			original.sprite.elapsed = elapsed
			player.sprite._refresh_frame()
			var atlas := player.sprite.texture as AtlasTexture
			check(atlas.atlas.resource_path.contains("WhiteSailor/Sheets/"), "Replacement frame required in " + name)
			check(player.sprite.finished() == original.sprite.finished(), "Action completion must match source: " + name)
		for side in [-1.0, 1.0]:
			player.sprite.facing = side
			player.sprite.elapsed = 0.0
			player.sprite._refresh_frame()
			var sampled: Dictionary = player.sprite.appearance.sample(name, clip, 0.0)
			var anchor_world: Vector2 = player.sprite.transform * sampled.anchor
			var expected := Vector2.ZERO
			if sampled.attachment == "wall":
				expected = player.sprite.wall_origin * Vector2(side, 1.0)
			elif sampled.attachment == "ceiling":
				expected = player.sprite.ceiling_origin
			check(anchor_world.distance_to(expected) < 0.001, "Anchored feet/hands for " + name)
	# Roof poses are authored upright and must not inherit a second 90-degree
	# turn from the original controller's rotated collision rectangle.
	player.sprite.body_rotation = PI / 2.0
	player.sprite.play("climb_ceiling", true)
	check(is_zero_approx(player.sprite.rotation), "Ceiling artwork remains upright")
	player.sprite.body_rotation = 0.0
	# A directed burst still rotates about the original GFX/body pivot.
	player.sprite.facing = 1.0
	player.sprite.gfx_rotation = PI / 4.0
	player.sprite.play("weak_dash_ready", true)
	var directed: Dictionary = player.sprite.appearance.sample("weak_dash_ready", source_clips.weak_dash_ready, 0.0)
	var expected_foot: Vector2 = player.sprite.pose_offset + (-player.sprite.pose_offset).rotated(PI / 4.0)
	check((player.sprite.transform * directed.anchor).distance_to(expected_foot) < 0.001, "Directed dash retains body pivot")
	player.sprite.gfx_rotation = 0.0
	# Hit artwork changes on the same source frame at which damage is queried.
	var attacks: Dictionary = player.tuning.attacks.AttackInfo
	var checks := {
		"attack1": attacks.AttackInfos[0].AttackCheckInfo,
		"attack2": attacks.AttackInfos[1].AttackCheckInfo,
		"attack3": attacks.AttackInfos[2].AttackCheckInfo,
		"heavy_attack": attacks.StrongAttackInfos[0].AttackCheckInfo,
		"jump_attack": attacks.JumpAttackInfos[0].AttackCheckInfo,
	}
	for name in ["attack1", "attack2", "attack3", "heavy_attack", "jump_attack"]:
		var clip: Dictionary = source_clips[name]
		var hit_time := float(checks[name].AttackCheckStartFrame) / 60.0
		check(player.sprite.appearance.sample(name, clip, maxf(0.0, hit_time - 0.00001)).index == 0, "Anticipation before hit: " + name)
		check(player.sprite.appearance.sample(name, clip, hit_time + 0.00001).index == 1, "Contact drawing at hit: " + name)
	# The shrine injects an extra timeline clip after actor._ready().
	var shrine: Dictionary = Assets.read_json(Assets.ROOT + "shrine_ambient.json")
	player.sprite.clips[shrine.player_idle.name] = shrine.player_idle
	player.sprite.play(shrine.player_idle.name, true)
	player.sprite.advance(0.3)
	check((player.sprite.texture as AtlasTexture).atlas.resource_path.contains("WhiteSailor/Sheets/"), "Shrine opening uses replacement art")
	var portable := load(PROFILE.get_base_dir().path_join("sprite_frames.res")) as SpriteFrames
	for name: String in profile.clips:
		check(portable.has_animation(name), "Portable SpriteFrames includes " + name)
		var clip: Dictionary = player.sprite.clips[name]
		var duration := 0.0
		for index in portable.get_frame_count(name):
			duration += portable.get_frame_duration(name, index) / portable.get_animation_speed(name)
			# This catches fixing a runtime offset while leaving the portable
			# PNG/SpriteFrames visibly unregistered (the original defect).
			var sequence: Dictionary = profile.sequences[profile.clips[name].sequence]
			var info: Dictionary = manifest.frames[sequence.sheet][int(sequence.cells[index])]
			var drawing := portable.get_frame_texture(name, index).get_image()
			var png := Image.load_from_file(PROFILE.get_base_dir().path_join(info.path))
			check(drawing.get_data() == png.get_data(), "Portable/runtime pixels agree: " + name)
		check(absf(duration - float(clip.length) / float(clip.speed)) < 0.0001, "Portable animation duration matches runtime: " + name)
	original.queue_free()
	player.queue_free()
	await process_frame
	if failures.is_empty():
		print("WHITE_SAILOR_PASS frames=", verified_frames, " actions=", profile.clips.size())
	quit(0 if failures.is_empty() else 1)
