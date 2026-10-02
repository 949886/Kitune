extends SceneTree
## Live source-level acquisition, telegraph, locked aim, first-hit damage and recovery.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const WaterCapture = preload("res://Samples/ArtDirection/Runtime/OriginalWaterCapture.gd")

var lab: Node
var rifle: Node
var combat: RefCounted
var shots: Array[Dictionary] = []
var reflection: Node
var transitions: Dictionary = {}
var effects: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func wait_state(expected: String, limit := 180) -> void:
	for frame in limit:
		if combat.state == expected:
			return
		await frames(1)
	assert(false, "Rifle failed to enter %s, current=%s" % [expected, combat.state])


func place_player(offset: Vector2) -> void:
	lab.player.position = (
		rifle.position + rifle.body_shape.position + offset - lab.player.body_shape.position
	)
	lab.player.velocity = Vector2.ZERO


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.stage.effect_started.connect(
		func(effect: Node2D):
			effects.append(
				{
					"key": effect.effect_key,
					"position": effect.global_position,
					"follow": effect.follow_actor
				}
			)
	)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
		if int(enemy.data.go) == 3213:
			rifle = enemy
	assert(rifle != null)
	combat = rifle.rifle_combat
	combat.state_changed.connect(
		func(value: String): transitions[value] = Engine.get_physics_frames()
	)
	var image: Image = combat.cues.lines.tracer.texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	assert(hash.finish().hex_encode() == combat.settings.actors["3213"].tracer.texture.pixel_sha256)
	# This factory crop has no water surface. Exercise the shared capture path
	# explicitly without adding a water effect to the playable source scene.
	reflection = WaterCapture.new()
	lab.viewport.add_child(reflection)
	reflection.configure(lab.stage, lab.player, lab.camera)
	var rifle_lines: Array = reflection.line_pairs.filter(
		func(pair: Dictionary): return not pair.get("target_marker", false)
	)
	assert(rifle_lines.size() == 6)
	var player_lines: Array = reflection.line_pairs.filter(
		func(pair: Dictionary):
			return (
				pair.source
				in [lab.player.targeting.presentation.line, lab.player.targeting.gamepad_aim.line]
			)
	)
	assert(player_lines.size() == 2)
	assert(reflection.line_pairs.size() == rifle_lines.size() + player_lines.size())
	assert(
		is_equal_approx(
			combat.cues.lines.aim.width * combat.cues.lines.aim.width_curve.sample(0), 0.654541
		)
	)
	assert(combat.cues.lines.aim.gradient.sample(33153.0 / 65535.0).a < 0.001)
	combat.shot_fired.connect(
		func(origin: Vector2, direction: Vector2, hit: Dictionary):
			shots.append({"origin": origin, "direction": direction, "hit": hit})
	)
	await frames(12)
	lab.player.set_physics_process(false)
	place_player(Vector2(200, 0))
	var wall := StaticBody2D.new()
	wall.collision_layer = Collision.SIGHT_SURFACE | Collision.RAY_SURFACE
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 180)
	shape.shape = rectangle
	wall.add_child(shape)
	lab.stage.add_child(wall)
	wall.position = rifle.position + rifle.body_shape.position + Vector2(100, 0)
	await frames(2)
	combat.target = lab.player
	await frames(90)
	assert(combat.state == "idle" and shots.is_empty(), "A wall must prevent acquisition")
	# Native rays ignore Platform, even when its geometry lies across the shot.
	wall.collision_layer = Collision.ONE_WAY
	await wait_state("ready")
	assert(rifle.motion == "AttackReady:0")
	assert(not rifle.ranged_presentation.aiming)
	await wait_state("confirm")
	assert(not rifle.motion_animation.is_processing())
	assert(combat.cues.lines.aim.visible)
	await frames(8)
	assert(rifle.ranged_presentation.aiming)
	for pair: Dictionary in reflection.line_pairs:
		assert(pair.copy.visible == pair.source.is_visible_in_tree())
		assert(pair.copy.points == pair.source.points)
		assert(pair.copy.material.get_shader_parameter("linear_framebuffer") == false)
	assert(absf(rifle.ranged_presentation.angle) < 0.1)
	var before: float = rifle.position.x
	await wait_state("shot")
	assert(not combat.cues.lines.aim.visible)
	await frames(1)
	assert(combat.cues.lines.tracer.visible)
	if DisplayServer.get_name() != "headless":
		lab.camera_rig.set_process(false)
		lab.camera.position = rifle.position + Vector2(100, -20)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_rifle_shot.png")
	await wait_state("post")
	assert(shots.size() == 1, "Only one ray may fire during a shot animation")
	var reload_time := (
		float(transitions.confirm - transitions.ready) / Engine.physics_ticks_per_second
	)
	var confirm_time := (
		float(transitions.shot - transitions.confirm) / Engine.physics_ticks_per_second
	)
	assert(absf(reload_time - 31.0 / 60.0) < 0.05)
	assert(absf(confirm_time - 0.5) < 0.05)
	assert(lab.stage.audio.last_selection.has("rifle_reload"))
	assert(lab.stage.audio.last_selection.has("rifle_shot"))
	assert(shots[0].hit.collider == lab.player)
	assert(lab.player.damage.health == 2, "Original rifle ray deals one runtime HP")
	assert(absf(rifle.position.x - before + 16.0) < 0.5, "Source recoil travels one unit backwards")
	assert(rifle.motion == "AttackPost:0")
	await frames(1)
	assert(not rifle.ranged_presentation.aiming)
	combat.target = null
	assert(not combat.cues.lines.aim.visible and not combat.cues.lines.tracer.visible)

	# A locked shot must miss after a dodge, rather than turn into a homing hit.
	lab.player.damage.reset()
	place_player(Vector2(200, -30))
	await frames(2)
	combat.target = lab.player
	await wait_state("confirm")
	while combat.elapsed < 0.37:
		await frames(1)
	var locked: float = rifle.ranged_presentation.angle
	place_player(Vector2(200, -150))
	await wait_state("shot")
	assert(is_equal_approx(rifle.ranged_presentation.angle, locked))
	await wait_state("post")
	assert(shots.size() == 2)
	assert(shots[-1].hit.is_empty() or shots[-1].hit.collider != lab.player)
	assert(lab.player.damage.health == 3)
	combat.target = null

	# Occlusion is checked again at firing, independently of earlier acquisition.
	place_player(Vector2(200, 0))
	await frames(2)
	combat.target = lab.player
	await wait_state("confirm")
	while combat.elapsed < 0.37:
		await frames(1)
	wall.position = rifle.position + rifle.body_shape.position + Vector2(100, 0)
	wall.collision_layer = Collision.SIGHT_SURFACE | Collision.RAY_SURFACE
	await wait_state("post")
	assert(shots.size() == 3 and shots[-1].hit.collider == wall)
	assert(effects[-1].key == "Eff_Enemy_Bullet_Ground")
	assert(absf(effects[-1].position.x - (wall.position.x - 4.0)) < 0.01)
	assert(effects[-1].follow == null)
	assert(lab.player.damage.health == 3)
	combat.target = null
	wall.collision_layer = Collision.ONE_WAY

	# Proximity cancels preparation into original-speed retreat, not a point-blank ray.
	place_player(Vector2(30, 0))
	await frames(2)
	combat.target = lab.player
	await wait_state("retreat")
	assert(not combat.cues.lines.aim.visible)
	assert(not rifle.ranged_presentation.aiming)
	combat.target = null

	place_player(Vector2(200, 0))
	await frames(2)
	combat.target = lab.player
	await wait_state("confirm")
	await frames(4)
	if DisplayServer.get_name() != "headless":
		lab.camera_rig.set_process(false)
		lab.camera.position = rifle.position + Vector2(100, -20)
		lab.camera.zoom = Vector2(2, 2)
		lab.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/art-direction/inari_rifle_combat.png")
	rifle.receive_study_hit({"Damage": 1000.0}, 1.0)
	await frames(45)
	assert(rifle.dead and shots.size() == 3)
	var muzzles := effects.filter(func(event: Dictionary): return event.key == "Eff_RifleMan_Shot")
	assert(muzzles.size() == 3)
	assert(muzzles.all(func(event: Dictionary): return event.follow == rifle))
	assert(not combat.cues.lines.aim.visible and not combat.cues.lines.tracer.visible)
	lab.queue_free()
	await process_frame
	print("RIFLE_COMBAT_PASS")
	quit()
