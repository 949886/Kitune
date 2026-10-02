extends SceneTree
## Actual gamepad attack input, native stack damage, selective hit-stop and recovery.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")

var lab: Node
var player: Node
var target: Node
var neighbor: Node
var phases: Array[String] = []
var hits: Array[float] = []
var effects: Array[String] = []
var sounds: Array[String] = []
var base := Vector2(-20000, -20000)


func _initialize() -> void:
	call_deferred("run")


func frames(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func until_phase(value: String, limit := 150) -> void:
	for frame in limit:
		if player.weak_dash.phase == value:
			return
		await frames(1)
	assert(false, "Weak dash did not reach phase: " + value)


func aim() -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = 1.0
	Input.parse_input_event(event)


func attack_button(pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	event.pressed = pressed
	Input.parse_input_event(event)


func setup(stacks: int) -> void:
	if is_instance_valid(lab):
		lab.queue_free()
		await frames()
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	player = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
	target = lab.stage.enemies.filter(func(enemy: Node): return enemy.data.kind == "EnemyRifleMan")[0]
	neighbor = lab.stage.enemies.filter(func(enemy: Node): return enemy.data.kind == "EnemyBowMan")[0]
	target.position = base
	neighbor.position = base + Vector2(4, 0)
	var center: Vector2 = target.position + target.body_shape.position
	var feet: Vector2 = center + Vector2.DOWN * target.body_shape.shape.size.y * 0.5
	var floor_body := StaticBody2D.new()
	floor_body.position = feet + Vector2(0, 25.0)
	floor_body.collision_layer = (
		Collision.SOLID | Collision.SIGHT_SURFACE | Collision.STATIC_SURFACE
	)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1000, 50)
	var shape := CollisionShape2D.new()
	shape.shape = rectangle
	floor_body.add_child(shape)
	lab.stage.add_child(floor_body)
	player.position = feet + Vector2(-90, -player.body_size.y * 0.5) - player.body_shape.position
	player.action_state = ""
	player.sprite.play("idle", true)
	target.kunai.weak_points = stacks
	target.kunai.reset_time = 5.0
	target.weakpoint_presentation.hit(stacks)
	phases.clear()
	hits.clear()
	effects.clear()
	sounds.clear()
	lab.stage.audio.event_started.connect(
		func(group: String, _handle: int):
			if group.begins_with("enemy_stack_hit_"):
				sounds.append(group)
	)
	player.weak_dash.phase_changed.connect(func(value: String): phases.append(value))
	player.weak_dash.hit_delivered.connect(func(_enemy: Node, amount: float): hits.append(amount))
	lab.stage.effect_started.connect(func(effect: Node): effects.append(effect.effect_key))
	aim()
	player.set_physics_process(true)
	await frames(12)
	assert(player.targeting.current == target, "The actual selector must supply the attack target")


func run() -> void:
	var constant_curve := {
		"m_Curve":
		[
			{"time": 0.0, "value": 2.0, "inSlope": 0.0, "outSlope": "Infinity"},
			{"time": 1.0, "value": 5.0, "inSlope": "Infinity", "outSlope": 0.0}
		]
	}
	assert(SourceCurve.evaluate(constant_curve, 0.5) == 2.0)
	assert(SourceCurve.evaluate(constant_curve, 1.0) == 5.0)
	for stacks in [1, 2, 3]:
		await setup(stacks)
		var before: float = target.health
		var neighbor_health: float = neighbor.health
		attack_button(true)
		await frames(1)
		attack_button(false)
		assert(player.weak_dash.active())
		assert(player.action_state == "weakpoint_execution")
		assert(not target.is_targetable)
		assert(not player.damage.receive(1.0), "Execution uses native state immunity")
		await until_phase("impact_wait")
		assert(hits.is_empty() and target.health == before)
		assert(sounds.is_empty(), "StackHit starts on damage, after the selected frame-stop")
		assert(player.source_time_scale == 0.0 and target.source_time_scale == 0.0)
		assert(Engine.time_scale == 1.0)
		assert(
			is_equal_approx(
				lab.stage.combat_clock.remaining,
				(
					player.combat.WeakPointAttackInfo.FrameStop[stacks - 1]
					* player.tuning.fixed_timestep
				)
			)
		)
		var position: Vector2 = player.position
		var animation_time: float = player.sprite.elapsed
		var target_animation: Node = target.motion_animation
		var track_time: float = (
			target_animation.tracks[0].time if not target_animation.tracks.is_empty() else -1.0
		)
		var marker_time: float = player.clock
		target.kunai.reset_time = 0.001
		neighbor.kunai.weak_points = 1
		neighbor.kunai.reset_time = 0.001
		var scaled: Node = lab.stage.spawn_effect("Eff_RifleMan_Shot", base, 0.0)
		var unscaled: Node = lab.stage.spawn_effect(
			"Eff_RifleMan_Shot", base, 0.0, false, null, false
		)
		var arrow: Node = lab.stage.spawn_arrow(base + Vector2(-700, -300), 0.0, 10.0, target)
		var arrow_start: Vector2 = arrow.position
		await frames(3)
		assert(player.position == position and player.sprite.elapsed == animation_time)
		assert(player.clock > marker_time)
		assert(target.kunai.weak_points == stacks and target.kunai.reset_time == 0.001)
		assert(neighbor.kunai.weak_points == 0, "Unselected weakness timers use unscaled delta")
		assert(scaled.emitters[0].clock == 0.0 and unscaled.emitters[0].clock > 0.0)
		assert(arrow.position.x > arrow_start.x, "Native Arrow has no time-scale implementation")
		assert(arrow.flight_effect.emitters[0].clock > 0.0)
		if track_time >= 0.0:
			assert(target_animation.tracks[0].time == track_time)
		await until_phase("post")
		assert(lab.stage.chromatic.intensity == lab.stage.chromatic.settings.intensity[stacks - 1])
		assert(hits == [float(player.combat.WeakPointAttackInfo.Damages[stacks])])
		assert(sounds == ["enemy_stack_hit_%d" % stacks])
		assert(target.health == maxf(0.0, before - hits[0]))
		assert(target.kunai.weak_points == 0 and target.is_targetable)
		assert(neighbor.health == neighbor_health)
		assert(lab.stage.combat_clock.scale_value == 1.0 and player.source_time_scale == 1.0)
		assert(player.collision_mask == Collision.SOLID)
		assert("Eff_Player_Attack_3" in effects)
		assert("Eff_WeaknessExposure_ver%d" % stacks in effects)
		assert(("Eff_PlayerThirdStack" in effects) == (stacks == 3))
		await until_phase("")
		assert(phases == ["ready", "impact_wait", "post", ""])
		assert(hits.size() == 1)
		assert(player.sprite.gfx_rotation == 0.0)
		assert(player.collision_mask == Collision.SOLID | Collision.ONE_WAY)
		print("WEAK_DASH_STACK ", stacks, " damage=", hits[0], " phases=", phases)
	# Forced death is a debug/retry escape: it must not strand this stage's clock.
	await setup(1)
	attack_button(true)
	await frames(1)
	attack_button(false)
	await until_phase("impact_wait")
	player.die(true)
	assert(not player.weak_dash.active() and lab.stage.combat_clock.scale_value == 1.0)
	assert(target.is_targetable, "Retry must also release the selected enemy's weakness timer")
	assert(player.sprite.gfx_rotation == 0.0 and hits.is_empty())
	lab.load_level(1)
	assert(lab.stage.combat_clock.scale_value == 1.0 and lab.player.source_time_scale == 1.0)
	if DisplayServer.get_name() != "headless":
		await capture_attack(2)
		await capture_attack(3)
	lab.queue_free()
	await frames()
	print("WEAK_DASH_PASS")
	quit()


func capture_attack(stacks: int) -> void:
	# Exercise the same input chain in the actual factory, outside the isolated
	# collision fixture. Save both the held impact pose and resumed hit effects.
	lab.load_level(0)
	player = lab.player
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.patrol.enabled = false
	target = lab.stage.enemies.filter(func(enemy: Node): return enemy.data.kind == "EnemyRifleMan")[0]
	player.position = target.position + Vector2(-60, 0)
	player.action_state = ""
	player.sprite.play("idle", true)
	aim()
	await frames(45)
	target.kunai.weak_points = stacks
	target.kunai.reset_time = 5.0
	target.weakpoint_presentation.hit(stacks)
	await frames(5)
	assert(player.targeting.current == target)
	attack_button(true)
	await frames(1)
	attack_button(false)
	await until_phase("impact_wait")
	await RenderingServer.frame_post_draw
	var suffix := "" if stacks == 3 else "_stack%d" % stacks
	root.get_texture().get_image().save_png(
		"res://tmp/art-direction/inari_weak_dash_hold%s.png" % suffix
	)
	await until_phase("post")
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://tmp/art-direction/inari_weak_dash_hit%s.png" % suffix
	)
