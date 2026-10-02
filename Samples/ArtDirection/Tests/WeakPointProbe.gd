extends SceneTree
## Original weak-point pixels, stack branches, range growth, contacts and lifetime.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var lab: Node
var bow: Node
var presentation: RefCounted


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func tick(delta: float) -> void:
	bow.kunai.update(delta)
	bow._sync_visuals()


func visible_stacks() -> int:
	var count := 0
	for group: Array in presentation.data.stacks:
		if group.all(func(go: Variant): return bow.visuals[go].visible):
			count += 1
	return count


func run() -> void:
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "weakpoints.json")
	assert(evidence.actors.size() == 6 and evidence.added_sprite_sha256.size() == 4)
	for key: String in evidence.added_sprite_sha256:
		var pixels: Image = Assets.texture(key).get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == evidence.added_sprite_sha256[key])
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
		enemy.set_physics_process(false)
		var marker: RefCounted = enemy.weakpoint_presentation
		assert(marker.data.stacks.size() == 3 and marker.data.range_members.size() == 3)
		assert(marker.data.animations.is_empty(), "The shipped range idle clip has no bindings")
		assert(marker.data.empty_range_clips.size() == 2)
		for group: Array in marker.data.stacks:
			assert(group.size() == 2)
			assert(group.all(func(go: Variant): return not enemy.visuals[go].visible))
		assert(
			marker.data.range_members.all(func(go: Variant): return not enemy.visuals[go].visible)
		)
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	presentation = bow.weakpoint_presentation
	lab.player.position = bow.position + Vector2(400, 0)
	await frames(2)
	assert(bow.receive_study_kunai(lab.player))
	assert(visible_stacks() == 0 and not presentation.range_active)
	bow.kunai.dash(lab.player)
	assert(visible_stacks() == 1 and presentation.range_active)
	tick(0.1)
	assert(is_equal_approx(presentation.range_scale, 1.0))
	bow.kunai.dash(lab.player)
	tick(0.05)
	assert(visible_stacks() == 2 and is_equal_approx(presentation.range_scale, 1.225))
	bow.kunai.dash(lab.player)
	tick(0.05)
	assert(visible_stacks() == 3 and is_equal_approx(presentation.range_scale, 1.61875))
	tick(0.05)
	assert(is_equal_approx(presentation.range_scale, 1.75))
	var go: Variant = presentation.data.range_members[0]
	var initial: Transform2D = bow.base_transforms[go]
	assert(is_equal_approx(bow.visuals[go].global_transform.x.length(), initial.x.length() * 1.75))
	var position: Vector2 = bow.visuals[go].global_position
	bow.position += Vector2(50, -12)
	bow._sync_visuals()
	assert(bow.visuals[go].global_position.is_equal_approx(position + Vector2(50, -12)))
	var fixed_pose: Transform2D = bow.visuals[go].global_transform
	bow.facing *= -1.0
	bow._sync_visuals()
	assert(bow.visuals[go].global_transform.is_equal_approx(fixed_pose))
	var marker_material: ShaderMaterial = bow.visuals[go].material
	var initial_flash: Variant = marker_material.get_shader_parameter("hit_blend")
	bow._set_flash(1.0)
	assert(marker_material.get_shader_parameter("hit_blend") == initial_flash)
	bow._set_flash(0.0)

	# Actual player contact also requests the source otherRenderers outline fade.
	lab.player.position = (
		Assets.matrix(presentation.data.range_transform).origin
		+ bow.position
		- bow.origin
		- lab.player.body_shape.position
	)
	await frames(2)
	tick(0.0)
	assert(presentation.contact_in_range)
	presentation.outline.step(float(bow.data.common.OutLineSpeed) * 0.5)
	for outline_go in presentation.outline.values:
		assert(is_equal_approx(float(presentation.outline.values[outline_go]), 0.3))
	presentation.outline.step(float(bow.data.common.OutLineSpeed) * 0.5)
	for outline_go in presentation.outline.values:
		assert(is_equal_approx(float(presentation.outline.values[outline_go]), 0.4))
	# Native Selected invokes only on a value change and falls back to range alpha.
	presentation.outline.set_selected(true)
	presentation.outline.step(float(bow.data.common.OutLineSpeed) * 0.5)
	for outline_go in presentation.outline.values:
		assert(is_equal_approx(float(presentation.outline.values[outline_go]), 0.85))
	presentation.outline.set_selected(true)
	assert(presentation.outline.tweens.size() == 1)
	presentation.outline.set_selected(false)
	presentation.outline.step(float(bow.data.common.OutLineSpeed) * 0.5)
	for outline_go in presentation.outline.values:
		assert(is_equal_approx(float(presentation.outline.values[outline_go]), 0.5125))
	presentation.outline.step(float(bow.data.common.OutLineSpeed) * 0.5)
	lab.player.position += Vector2(1000, 0)
	await frames(2)
	tick(0.0)
	assert(not presentation.contact_in_range)
	presentation.outline.step(float(bow.data.common.OutLineSpeed))
	for outline_go in presentation.outline.values:
		assert(is_zero_approx(float(presentation.outline.values[outline_go])))
	if DisplayServer.get_name() != "headless":
		lab.player.position = bow.position + Vector2(90, 0)
		await frames(45)
		tick(0.0)
		presentation.outline.step(float(bow.data.common.OutLineSpeed))
		await frames(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/inari_weakpoint_stacks.png"
		)
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/inari_weakpoint_outline.png"
		)

	bow.kunai.reset_time = 0.01
	tick(0.02)
	assert(visible_stacks() == 3, "Timeout clears on the update after the clock reaches zero")
	tick(0.0)
	assert(bow.kunai.weak_points == 0 and visible_stacks() == 0 and not presentation.range_active)
	assert(is_equal_approx(presentation.range_scale, 1.75))
	# Reset hides but preserves the range scale, matching ResetWeakPointStack.
	bow.kunai.dash(lab.player)
	tick(0.05)
	assert(visible_stacks() == 1 and is_equal_approx(presentation.range_scale, 1.1875))
	bow.receive_study_hit({"Damage": 10000.0}, 1.0)
	assert(bow.dead and bow.kunai.weak_points == 0 and visible_stacks() == 0)
	assert(not presentation.range_active)
	lab.queue_free()
	await process_frame
	print("WEAK_POINT_PASS")
	quit()
