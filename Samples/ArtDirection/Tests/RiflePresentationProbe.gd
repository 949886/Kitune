extends SceneTree
## Source rifle parts, angular sprite boundaries and imported combat animation frames.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	var rifles: Array[Node] = []
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyRifleMan":
			rifles.append(enemy)
	assert(rifles.size() == 3)
	for enemy: Node in rifles:
		var pose: RefCounted = enemy.ranged_presentation
		var source: Dictionary = pose.settings
		var arm: Dictionary = source.RotationSpriteInfos[0]
		var body: Dictionary = source.NonRotationHolderInfos[1]
		var arm_visual: Node2D = enemy.visuals[arm.go]
		var body_visual: Node2D = enemy.visuals[body.go]
		assert(not arm_visual.visible)
		assert(enemy.visuals[source.NonRotationHolder[0]].visible)
		pose.set_aiming(true)
		assert(arm_visual.visible and not enemy.visuals[source.NonRotationHolder[0]].visible)
		pose.set_angle(-45.0)
		assert(arm_visual.current_sprite == arm.infos[0].sprite, "RotationPart uses strict <")
		assert(body_visual.z_index == lab.stage.sort_depth(body.infos[0].sort))
		pose.set_angle(-44.99)
		assert(arm_visual.current_sprite == arm.infos[1].sprite)
		assert(body_visual.z_index == lab.stage.sort_depth(body.infos[1].sort))
		for facing in [-1.0, 1.0]:
			enemy.facing = facing
			pose.set_angle(0.0)
			var baseline := arm_visual.global_transform
			pose.set_angle(30.0)
			var expected := baseline * Transform2D(-deg_to_rad(30.0), Vector2.ZERO)
			assert(arm_visual.global_transform.is_equal_approx(expected))
			# Reapplying after body motion cannot accumulate gun rotation.
			for step in 10:
				enemy._sync_visuals()
			assert(arm_visual.global_transform.is_equal_approx(expected))
		pose.set_aiming(false)
		assert(not arm_visual.visible and enemy.visuals[source.NonRotationHolder[0]].visible)
		assert(pose.angle == 0.0)

		var reload: Array = pose.animation("AttackReady", 0)
		var kick: Array = pose.animation("AttackReady", 1)
		assert(reload[0].clip.ends_with("Reload") and kick[0].clip.ends_with("KickConfirm"))
		assert(is_equal_approx(float(reload[0].length) / float(reload[0].speed), 31.0 / 60.0))
		var shot: Dictionary = enemy.data.combat_animations["Attack:0"]
		assert(shot.parameter == "Angle" and shot.variants.size() == 5)
		var unique_frames: Dictionary = {}
		for variant: Dictionary in shot.variants:
			var selected: Array = pose.animation("Attack", 0, variant.threshold)
			assert(selected == variant.tracks and selected.size() == 3)
			for track: Dictionary in selected:
				assert(enemy.visuals.has(track.go))
				assert(not track.frames.is_empty())
				for frame: Array in track.frames:
					assert(Assets.texture(frame[1]).get_image() != null)
					unique_frames[frame[1]] = true
		assert(unique_frames.size() > 20, "Five shot directions must not reuse one pose")
		enemy.play_combat_motion("AttackReady")
		assert(enemy.motion == "AttackReady:0")
		assert(enemy.motion_animation.tracks[0].node.current_sprite == reload[0].frames[0][1])
		enemy.motion_animation.advance(1.0)
		assert(enemy.motion_animation.tracks[0].finished)
		assert(enemy.motion_animation.tracks[0].node.current_sprite == reload[0].frames[-1][1])
		pose.set_aiming(true)
		pose.set_angle(45.0)
		enemy.play_combat_motion("Attack", 0, 45.0)
		enemy.motion_animation.advance(1.0)
		var shot_frames: Dictionary = {}
		for track: Dictionary in enemy.motion_animation.tracks:
			shot_frames[track.clip.go] = track.node.current_sprite
		enemy.position.x += 8.0
		enemy._sync_visuals()
		for go in shot_frames:
			assert(enemy.visuals[go].current_sprite == shot_frames[go])
		pose.set_aiming(false)

	if DisplayServer.get_name() != "headless":
		# Preserve a real level view with the original gun parts visible.
		var enemy: Node2D = rifles[1]
		enemy.motion_animation.tracks.clear()
		enemy.facing = 1.0
		enemy.ranged_presentation.set_aiming(true)
		enemy.ranged_presentation.set_angle(30.0)
		lab.player.set_physics_process(false)
		lab.player.position = enemy.position + Vector2(100, -40)
		lab.camera_rig.set_process(false)
		lab.camera.position = enemy.position + Vector2(40, -24)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
		for step in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_rifle_aim.png")
	for enemy: Node in rifles:
		enemy.ranged_presentation.set_aiming(true)
		enemy._die(null)
		for go in enemy.ranged_presentation.settings.RotationHolder:
			if enemy.visuals.has(go):
				assert(not enemy.visuals[go].visible, "Death must hide the separate aiming parts")
		assert(enemy.visuals[enemy.data.primary_visual].visible)
	lab.queue_free()
	await process_frame
	print("RIFLE_PRESENTATION_PASS")
	quit()
