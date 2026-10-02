extends SceneTree
## Original bow pixels, hidden aiming parts and ranged/melee Animator branches.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	var bow: Node
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	assert(bow != null and int(bow.data.go) == 3454)
	var pose: RefCounted = bow.ranged_presentation
	var arm: Dictionary = pose.settings.RotationSpriteInfos[0]
	var head: Dictionary = pose.settings.NonRotationHolderInfos[1]
	var arm_visual: Node2D = bow.visuals[arm.go]
	var head_visual: Node2D = bow.visuals[head.go]
	pose.set_aiming(false)
	assert(not arm_visual.visible)
	assert(
		not bow.visuals[3400.0].visible, "An inactive child stays hidden when its parent activates"
	)
	assert(bow.visuals.has(3378.0) and bow.visuals[3378.0].current_sprite == null)
	pose.set_aiming(true)
	assert(arm_visual.visible and not bow.visuals[bow.data.primary_visual].visible)
	pose.set_angle(-45.0)
	assert(arm_visual.current_sprite == arm.infos[0].sprite)
	assert(head_visual.z_index == lab.stage.sort_depth(head.infos[0].sort))
	pose.set_angle(-44.99)
	assert(arm_visual.current_sprite == arm.infos[1].sprite)
	assert(head_visual.z_index == lab.stage.sort_depth(head.infos[1].sort))
	pose.set_angle(-10.0)
	assert(arm_visual.current_sprite == arm.infos[1].sprite)
	pose.set_angle(-9.99)
	assert(arm_visual.current_sprite == arm.infos[2].sprite)
	for facing in [-1.0, 1.0]:
		bow.facing = facing
		pose.set_angle(0.0)
		var baseline := arm_visual.global_transform
		pose.set_angle(30.0)
		var expected := baseline * Transform2D(-deg_to_rad(30.0), Vector2.ZERO)
		for frame in 10:
			bow._sync_visuals()
		assert(arm_visual.global_transform.is_equal_approx(expected))

	var reload: Array = pose.animation("AttackReady", 0)
	var melee: Array = pose.animation("AttackReady", 1)
	assert(
		reload[0].clip.ends_with("Bow_AttackReady") and melee[0].clip.ends_with("MeleeAttackReady")
	)
	assert(is_equal_approx(float(reload[0].length) / float(reload[0].speed), 19.0 / 48.0))
	assert(pose.animation("AttackPost", 0).is_empty(), "The bow has no ranged Post transition")
	var unique: Dictionary = {}
	for variant: Dictionary in bow.data.combat_animations["Attack:0"].variants:
		var selected: Array = pose.animation("Attack", 0, variant.threshold)
		assert(selected == variant.tracks and selected.size() == 1)
		for frame: Array in selected[0].frames:
			assert(Assets.texture(frame[1]).get_image() != null)
			unique[frame[1]] = true
	assert(unique.size() > 20)
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "bow_presentation.json")
	for key: String in evidence.added_sprite_sha256:
		var pixels: Image = Assets.texture(key).get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == evidence.added_sprite_sha256[key])

	pose.set_aiming(false)
	bow.play_combat_motion("AttackReady", 0)
	assert(is_equal_approx(bow.motion_duration, 19.0 / 48.0))
	bow.motion_animation.advance(1.0)
	assert(bow.visuals[bow.data.primary_visual].current_sprite == reload[0].frames[-1][1])
	pose.set_aiming(true)
	pose.set_angle(30.0)
	bow.play_combat_motion("AttackConfirm", 0)
	assert(bow.motion_animation.tracks.size() == 1, "Initially empty Light renderer must bind")
	bow.motion_animation.advance(0.06)
	bow.motion_animation.advance(0.0)
	assert(bow.visuals[3378.0].current_sprite != null and bow.visuals[3378.0].visible)
	if DisplayServer.get_name() != "headless":
		lab.player.set_physics_process(false)
		lab.player.position = bow.position + Vector2(300, 0)
		lab.camera_rig.set_process(false)
		lab.camera.position = bow.position + Vector2(40, -24)
		lab.camera.zoom = Vector2(3, 3)
		lab.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bow_aim.png")
	pose.set_aiming(false)
	bow.play_combat_motion("Attack", 0, 45.0)
	bow.motion_animation.advance(0.12)
	bow.motion_animation.advance(0.0)
	var shot_frame: Variant = bow.visuals[bow.data.primary_visual].current_sprite
	bow.position.x += 8.0
	bow._sync_visuals()
	assert(bow.visuals[bow.data.primary_visual].current_sprite == shot_frame)
	bow.play_combat_motion("AttackCancel", 0)
	assert(bow.motion_animation.tracks[0].clip.clip.ends_with("AttackCancel"))
	bow._die(null)
	for visual: Node2D in bow.visuals.values():
		assert(not visual.visible)
	print("BOW_PRESENTATION_PASS pixels=", evidence.added_sprite_sha256.size())
	lab.queue_free()
	await process_frame
	quit()
