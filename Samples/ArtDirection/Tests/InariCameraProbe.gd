extends SceneTree
## Source framing, frame-rate-independent damping, outer bounds and teleport hold.

const Rig = preload("res://Samples/ArtDirection/Runtime/InariCameraRig.gd")
const Player = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	root.add_child(viewport)
	var player := Player.new()
	viewport.add_child(player)
	player.set_physics_process(false)
	var source: Dictionary = Assets.read_json(Assets.ROOT + "camera.json")
	assert(source.follow.game_object == "Player")
	assert(source.framing.m_LookaheadTime == 0.0)
	var rig := Rig.new()
	viewport.add_child(rig)
	rig.configure_2d({}, player, source)
	rig.set_process(false)

	# The shipped perspective lens spans 421.607 pixels on the gameplay plane.
	var height := 2.0 * 21.5 * tan(deg_to_rad(63.0) / 2.0) * 16.0
	assert(is_equal_approx(rig.view_size.y, height))
	assert(is_equal_approx(rig.camera_2d.zoom.y, 450.0 / height))
	var body_center: Vector2 = player.position + player.body_shape.position
	var normalized := (body_center - rig.camera_2d.position) / rig.view_size + Vector2.ONE * 0.5
	assert(normalized.distance_to(Vector2(0.5, 0.6)) < 0.00001)

	# Independent exponential oracle: 0.55 seconds leaves 1% error. Subdividing
	# that interval into 30, 60 or 144 steps must yield the same camera position.
	for steps in [30, 60, 144]:
		player.position = Vector2.ZERO
		rig.warp_to_target()
		var start := rig.camera_2d.position
		player.position.x += 40.0
		for step in steps:
			rig.advance(0.55 / steps)
		assert(absf(rig.camera_2d.position.x - start.x - 39.6) < 0.001)

	# Sudden movement crosses the 30% soft zone; hard correction keeps the
	# target inside it even though the damped displacement would be too small.
	player.position += Vector2(2000, -2000)
	rig.advance(1.0 / 60.0)
	normalized = (
		(player.position + rig.target_offset - rig.camera_2d.position) / rig.view_size
		+ Vector2.ONE * 0.5
	)
	assert(normalized.x <= 0.65001 and normalized.y >= 0.44999)
	assert(is_equal_approx(rig.teleport_freeze_time, 0.075))
	var frozen := rig.camera_2d.position
	player.position += Vector2(200, 100)
	player.teleported.emit(Vector2.ZERO, player.position)
	for step in 5:
		rig.advance(1.0 / 60.0)
		assert(rig.camera_2d.position == frozen)
	rig.advance(1.0 / 60.0)
	assert(rig.camera_2d.position != frozen)
	rig.warp_to_target()
	normalized = (
		(player.position + rig.target_offset - rig.camera_2d.position) / rig.view_size
		+ Vector2.ONE * 0.5
	)
	assert(normalized.distance_to(Vector2(0.5, 0.6)) < 0.00001)
	assert(rig.freeze_remaining == 0.0)
	var baseline := rig.camera_2d.position
	player.camera_shake_requested.emit("Attack")
	rig.impulse.phase = 0.0
	rig._process(0.0)
	assert(rig.camera_2d.offset.distance_to(Vector2(12, -12)) < 0.001)
	assert(rig.camera_2d.position == baseline, "Impulse must not alter follow history")
	assert(
		(
			rig.camera_2d.get_screen_center_position().distance_to(baseline + rig.camera_2d.offset)
			< 0.001
		)
	)
	rig._process(1.0)
	assert(rig.camera_2d.offset == Vector2.ZERO and rig.camera_2d.position == baseline)
	player.camera_shake_requested.emit("Attack")
	rig.warp_to_target()
	assert(rig.impulse.active.is_empty() and rig.camera_2d.offset == Vector2.ZERO)
	_verify_conversation(viewport, player, source)
	viewport.queue_free()
	await process_frame
	print("INARI_CAMERA_PASS")
	quit()


func _verify_conversation(viewport: SubViewport, player: Node2D, gameplay: Dictionary) -> void:
	var source := gameplay.duplicate(true)
	var ambient: Dictionary = Assets.read_json(Assets.ROOT + "shrine_ambient.json")
	source.merge(ambient.camera, true)
	assert(source.follow.game_object == "ShotPoint")
	assert(is_equal_approx(source.excerpt.sample_time, ambient.pose_evidence[0].sample_time))
	var rig := Rig.new()
	viewport.add_child(rig)
	rig.configure_2d({}, player, source)
	rig.set_process(false)
	# Independent source values: Recorded (43) follows (0, 11.5), FOV 60,
	# camera distance 21.5 and centered framing, with no player body offset.
	assert(rig.target != player and rig.target.name == "ShotPoint")
	assert(rig.target_offset == Vector2.ZERO)
	assert(rig.camera_2d.position.distance_to(Vector2(0, -184)) < 0.001)
	var height := 2.0 * 21.5 * tan(deg_to_rad(60.0) / 2.0) * 16.0
	assert(absf(rig.view_size.y - height) < 0.001)
	assert(is_equal_approx(rig.camera_2d.zoom.y, 450.0 / height))
	for point in [Vector2(-240, -80), Vector2(0, -80), Vector2(240, -80)]:
		player.position = point
		rig.advance(1.0)
		assert(rig.camera_2d.position.distance_to(Vector2(0, -184)) < 0.001)
		var normalized: Vector2 = (
			(point - rig.camera_2d.position) / rig.view_size + Vector2.ONE * 0.5
		)
		assert(normalized.x > 0.0 and normalized.x < 1.0)
		assert(normalized.y > 0.0 and normalized.y < 1.0)
	player.teleported.emit(Vector2.ZERO, player.position)
	rig.advance(1.0)
	rig.warp_to_target()
	assert(rig.camera_2d.position.distance_to(Vector2(0, -184)) < 0.001)
