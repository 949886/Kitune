extends SceneTree
## Original melee cue timing, cubic motion, material binding and Write Defaults.

var lab: Node
var bow: Node
var flash: Node2D


func _initialize() -> void:
	call_deferred("run")


func sample(time: float) -> void:
	for track: Dictionary in bow.motion_animation.tracks:
		track.time = time
		track.finished = false
	bow.motion_animation.advance(0.0)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await process_frame
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	flash = bow.visuals[3400.0]
	bow.motion_animation.set_process(false)
	bow.ranged_presentation.set_aiming(false)
	assert(not flash.visible)
	var original_frame: Transform2D = bow.base_transforms[3400.0]
	var initial_material: String = flash.data.material
	flash.set_animation_material("Mat_Default")
	assert(flash.current_material == "Mat_Default")
	bow.play_combat_motion("AttackConfirm", 1)
	assert(bow.motion_animation.tracks.size() == 5)
	assert(is_equal_approx(bow.motion_duration, 1.0 / 3.0))
	assert(not flash.visible and flash.current_material != initial_material)
	assert(flash.current_material == "Mat_LampEmission 2")
	assert(flash.material != null)
	for track: Dictionary in bow.motion_animation.tracks:
		assert(not track.clip.has("unsupported_bindings"))

	sample(1.0 / 60.0 - 0.000001)
	assert(not flash.visible)
	sample(1.0 / 60.0 + 0.000001)
	assert(flash.visible)
	# At half of the first cubic segment the source curve is exactly halfway
	# between its endpoints; the authored starting X differs from the prefab.
	sample(1.0 / 24.0)
	var expected := Vector2(
		((0.747 + 1.313) * 0.5 - 0.757) * 16.0, (1.210 - (1.210 + 0.884) * 0.5) * 16.0
	)
	assert(flash.animation_offset.distance_to(expected) < 0.00002)
	for facing in [float(bow.data.facing), -float(bow.data.facing)]:
		bow.facing = facing
		bow._sync_visuals()
		var point: Vector2 = original_frame.origin + expected
		if facing != float(bow.data.facing):
			point.x = 2.0 * float(bow.data.gfx_position[0]) - point.x
		point += bow.position - bow.origin
		assert(flash.global_position.distance_to(point) < 0.001)
		for frame in 10:
			sample(1.0 / 24.0)
		assert(
			flash.global_position.distance_to(point) < 0.001,
			"Offsets must not accumulate or reverse after animation sampling"
		)
	bow.facing = float(bow.data.facing)
	sample(0.1)
	assert(
		(
			flash.animation_offset.distance_to(Vector2((1.313 - 0.757) * 16, (1.210 - 0.884) * 16))
			< 0.00002
		)
	)
	assert(flash.visible)
	if DisplayServer.get_name() != "headless":
		lab.player.set_physics_process(false)
		lab.player.position = bow.position + Vector2(300, 0)
		lab.camera_rig.set_process(false)
		lab.camera.position = bow.position + Vector2(30, -24)
		lab.camera.zoom = Vector2(3, 3)
		lab.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_bow_melee_flash.png")
	var end: float = bow.motion_animation.tracks[0].clip.length
	sample(end - 0.000001)
	assert(flash.visible)
	sample(end)
	assert(not flash.visible)

	# Check interruption as well as natural completion: Idle restores source
	# values even though Idle only contains a body sprite track.
	sample(0.1)
	bow.play_motion("Idle")
	assert(not flash.visible and flash.animation_visibility == null)
	assert(flash.animation_offset == Vector2.ZERO)
	assert(flash.current_material == initial_material)
	assert(flash.current_sprite == flash.data.sprite)
	assert(
		bow.visuals[3378.0].current_sprite == null,
		"The ranged cue returns to its original empty sprite"
	)
	bow.play_combat_motion("AttackConfirm", 1)
	sample(0.1)
	bow.ranged_presentation.set_aiming(true)
	assert(not flash.visible, "An animated child cannot bypass the hidden holder")
	bow.ranged_presentation.set_aiming(false)
	assert(flash.visible)
	bow._die(null)
	assert(not flash.visible)
	print("BOW_FLASH_PASS")
	lab.queue_free()
	await process_frame
	quit()
