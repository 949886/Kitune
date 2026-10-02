extends SceneTree
## Native dash-attack frame data, rotated pivots and the distinct recovery landing.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")


func _initialize() -> void:
	call_deferred("run")


func frames(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func solid(parent: Node, position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Collision.SOLID | Collision.SIGHT_SURFACE | Collision.STATIC_SURFACE
	body.position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	parent.add_child(body)
	return body


func run() -> void:
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "dash_attack.json")
	assert(evidence.sprites.size() == 33)
	assert(evidence.queries_start_in_colliders)
	for key: String in evidence.sprites:
		var info := Assets.sprite_info(key)
		var image := Image.load_from_file(Assets.ROOT + info.path)
		image.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_data())
		assert(hash.finish().hex_encode() == evidence.sprites[key])
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	var player: Node = lab.player
	player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
	var enemy: Node = lab.stage.enemies[0]
	var original_position: Vector2 = enemy.position
	enemy.position = Vector2(-20000, -20000)
	var center: Vector2 = enemy.position + enemy.body_shape.position
	var feet: Vector2 = center + Vector2.DOWN * enemy.body_shape.shape.size.y * 0.5
	var floor_body := solid(lab.stage, feet + Vector2(0, 25.001), Vector2(1000, 50))
	var distance: float = (
		player.combat.WeakPointAttackInfo.AttackMovementInfo.Distance * player.units
	)
	for side: float in [-1.0, 1.0]:
		player.position = (
			feet + Vector2(-side * 100, -player.body_size.y * 0.5) - player.body_shape.position
		)
		await frames()
		var path: Dictionary = enemy.kunai.weak_attack_path(player)
		var height_difference: float = absf(enemy.body_shape.shape.size.y - player.body_size.y)
		assert(path.approach == center + Vector2.DOWN * height_difference * 0.5)
		# GetGroundEdgeOffsetByDirection starts its forward probe at the enemy's
		# outer foot corner. A ground hit retains that extra half-width.
		var landing_distance: float = (
			distance + enemy.body_shape.shape.size.x * 0.5 - player.body_size.x * 0.5
		)
		var expected: Vector2 = feet + Vector2(side * landing_distance, -player.body_size.y * 0.5)
		assert(path.recovery.is_equal_approx(expected))
		assert(path.grounded)
		assert(path.approach != path.recovery)
		for stacks in range(4):
			enemy.kunai.weak_points = stacks
			assert(enemy.kunai.weak_attack_path(player).recovery == path.recovery)
		var inside: Vector2 = enemy.kunai._unity(floor_body.global_position)
		assert(not enemy.kunai._ray(inside, inside + Vector2.UP).is_empty())
		var wall_x := center.x + side * 42.0
		var wall := solid(lab.stage, Vector2(wall_x, feet.y - 60), Vector2(8, 120))
		await frames()
		var blocked: Dictionary = enemy.kunai.weak_attack_path(player)
		assert(absf(blocked.recovery.x - center.x) < absf(path.recovery.x - center.x))
		assert(
			blocked.approach == path.approach,
			"Recovery obstacles must not change the approach target"
		)
		wall.collision_layer = Collision.SOLID
		await frames()
		var unrelated: Dictionary = enemy.kunai.weak_attack_path(player)
		assert(
			unrelated.recovery == path.recovery,
			"Doors and other solid layers are absent from native Default/Static masks"
		)
		wall.queue_free()
		await frames()

	floor_body.queue_free()
	player.position = feet + Vector2(-100, -150) - player.body_shape.position
	await frames()
	var airborne: Dictionary = enemy.kunai.weak_attack_path(player)
	assert(not airborne.grounded)
	assert(airborne.approach != airborne.recovery)
	# Clip timestamps and original speed are separate: the full ready animation
	# lasts about 0.09167 seconds; the falling recovery lasts about 0.25641.
	for clip_name: String in evidence.clips:
		var clip: Dictionary = evidence.clips[clip_name]
		assert(player.sprite.clips[clip_name] == clip)
		for side in [-1.0, 1.0]:
			player.sprite.facing = side
			player.sprite.gfx_rotation = 0.63
			player.sprite.play(clip_name, true)
			for frame: Array in clip.frames:
				player.sprite.elapsed = frame[0]
				player.sprite._refresh_frame()
				var info := Assets.sprite_info(frame[1])
				var offset := Vector2(info.offset[0] * side, info.offset[1]).rotated(0.63)
				assert(player.sprite.position.is_equal_approx(player.sprite.pose_offset + offset))
				assert(player.sprite.texture == Assets.texture(frame[1]))
				assert(is_equal_approx(player.sprite.rotation, 0.63))
		player.sprite.play(clip_name, true)
		player.sprite.advance(float(clip.length) / float(clip.speed) - 0.00001)
		assert(not player.sprite.finished())
		player.sprite.advance(0.00002)
		assert(player.sprite.finished())
	player.sprite.gfx_rotation = 0.0
	enemy.position = original_position
	if DisplayServer.get_name() != "headless":
		player.position = enemy.position + Vector2(80, 0)
		player.sprite.facing = -1.0
		player.sprite.play("weak_dash_ready", true)
		player.sprite.advance(0.04)
		await frames(40)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/inari_dash_attack_ready.png"
		)
	lab.queue_free()
	await process_frame
	print("DASH_ATTACK_MOTION_PASS")
	quit()
