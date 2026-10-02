extends SceneTree
## Native volume overlaps and playable entry/exit. Depth is checked against an
## independent exponential oracle, including projected geometry and lighting.
var lab: Node
var simulate_loading := false


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func realtime(seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < until:
		await frames(1)


func press(action: String, count: int) -> void:
	Input.action_press(lab.player.input_action(action))
	await frames(count)
	Input.action_release(lab.player.input_action(action))
	await frames(2)


func zone_by_go(go: int) -> Node:
	for zone: Node in lab.stage.camera_zones.zones:
		if int(zone.source.go) == go:
			return zone
	return null


func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/camera-zone-" + name + ".png"
		)


func run() -> void:
	root.size = Vector2i(1280, 720)
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(2, 6)
	await frames(25)
	await realtime(0.22)
	var zone: Node = zone_by_go(3030)
	var rig: Node = lab.camera_rig
	assert(zone.inside and zone.entries == 1 and not zone.consumed)
	assert(rig.target == lab.stage.camera_zones.marker)
	var origin: Vector2 = lab.player.position + rig.player_origin_offset
	var expected := Vector2(origin.x, lerpf(zone.position.y, origin.y, 0.2))
	assert(rig.target.position.distance_to(expected) < 0.01)
	assert(not rig.framing.m_UnlimitedSoftZone)
	# Returning camera ownership reconciles a soft timer that expired while
	# the original Timeline camera was authoritative.
	lab.stage.camera_zones._soft_transition(zone)
	assert(rig.framing.m_UnlimitedSoftZone)
	rig.source.follow.fixed_position = [0, 0]
	lab.stage.camera_zones.advance_realtime(0.21)
	assert(rig.framing.m_UnlimitedSoftZone)
	rig.source.follow.erase("fixed_position")
	await frames(2)
	assert(not rig.framing.m_UnlimitedSoftZone)
	# Gallery/reference pausing must not consume a once-only volume.
	lab.set_controls_enabled(false)
	await frames(5)
	lab.set_controls_enabled(true)
	await frames(5)
	assert(zone.inside and not zone.consumed and zone.entries == 1)
	await capture("fixed")
	assert(lab.stage.machinery.battle.doors[11863].is_open)
	assert(not lab.stage.machinery.battle.doors[11786].is_open)
	await press("left", 45)
	await capture("exit")
	assert(zone.consumed and zone.exits == 1 and not zone.inside)
	assert(rig.target == lab.player)
	assert(lab.completed)
	await press("right", 50)
	assert(zone.entries == 1 and rig.target == lab.player)
	# Source reset restores the region as a fresh instance.
	lab.load_level(2, 6)
	await frames(10)
	assert(zone_by_go(3030).entries == 1 and not zone_by_go(3030).consumed)
	# WaitForSceneLoadComplete defers fixed-camera entry, then releases the soft
	# zone after the authored real-time delay. Geometry still reports overlap.
	simulate_loading = true
	lab.load_level(2, 6)
	lab.stage.camera_zones.loading = func(): return simulate_loading
	await frames(5)
	assert(zone_by_go(3030).inside and lab.stage.camera_zones.fixed_zone == null)
	assert(lab.camera_rig.target == lab.player)
	simulate_loading = false
	await frames(3)
	assert(lab.camera_rig.target == lab.stage.camera_zones.marker)
	assert(lab.camera_rig.framing.m_UnlimitedSoftZone)
	# Source WaitForSecondsRealtime must expire even in slow motion. A fixed
	# number of simulation frames is not evidence of real-time expiration.
	Engine.time_scale = 0.1
	await realtime(0.22)
	Engine.time_scale = 1.0
	assert(not lab.camera_rig.framing.m_UnlimitedSoftZone)
	# Existing platform gameplay begins in an authored pull-back volume. Verify
	# that ordinary walking keeps its native distance control active.
	lab.load_level(2, 0)
	await frames(30)
	assert(zone_by_go(4622).inside and lab.camera_rig.target_depth == -1.5)
	assert(lab.camera_rig.camera_distance > float(lab.camera_rig.source.distance))
	await press("right", 15)
	assert(zone_by_go(4622).inside)
	# The factory contains a repeatable distance volume. Relocate only this
	# geometry fixture; the fixed-camera practice above traverses real terrain.
	lab.load_level(0)
	await frames(8)
	rig = lab.camera_rig
	zone = zone_by_go(2871)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
	lab.player.position = zone.to_global(zone.get_child(0).position) - rig.player_origin_offset
	await frames(5)
	assert(zone.inside and rig.target_depth == -3.5 and rig.source.damping[2] == 5.0)
	# CameraDistanceTrigger's five-second damping leaves one percent residual.
	rig.set_process(false)
	rig._set_camera_distance(21.5)
	for step in 60:
		rig.advance(5.0 / 60.0)
	assert(absf(rig.camera_distance - (25.0 - 3.5 * 0.01)) < 0.0001)
	await frames(2)
	assert(is_equal_approx(lab.stage.projection.distance, rig.camera_distance))
	for key: Vector2 in lab.stage.projection.planes:
		var plane: Node2D = lab.stage.projection.planes[key]
		if plane.visible:
			assert(
				is_equal_approx(plane.scale.x, rig.camera_distance / (rig.camera_distance + key.x))
			)
	assert(is_equal_approx(lab.stage.lighting.last_distance, rig.camera_distance))
	await capture("distance")
	var inside: Vector2 = lab.player.position
	lab.player.position += Vector2(2000, 0)
	await frames(5)
	assert(not zone.inside and not zone.consumed)
	assert(rig.target_depth == 0.0 and rig.source.damping[2] == 1.0)
	lab.player.position = inside
	await frames(5)
	assert(zone.inside and zone.entries >= 2)
	# A bound cutscene camera remains authoritative even inside a native zone.
	lab.load_level(1)
	await frames(10)
	rig = lab.camera_rig
	zone = zone_by_go(129)
	var shot: Node = rig.target
	lab.player.position = zone.to_global(zone.get_child(0).position) - rig.player_origin_offset
	await frames(10)
	assert(zone.inside and rig.target == shot and rig.source.follow.has("fixed_position"))
	lab.queue_free()
	await frames(2)
	print("CAMERA_ZONE_PROBE_PASS")
	quit()
