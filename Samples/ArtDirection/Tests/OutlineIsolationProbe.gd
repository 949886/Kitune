extends SceneTree
## Hold the player pose constant while toggling the enemy's outline.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func hash_bytes(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func visible_bytes(image: Image) -> PackedByteArray:
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	for index in range(0, bytes.size(), 4):
		if bytes[index + 3] == 0:
			bytes[index] = 0
			bytes[index + 1] = 0
			bytes[index + 2] = 0
	return bytes


func run() -> void:
	var evidence: Dictionary = Assets.read_json(Assets.ROOT + "player_frame_proof.json")
	for pose: String in evidence:
		var proof: Dictionary = evidence[pose]
		var info := Assets.sprite_info(proof.sprite)
		var atlas := Image.load_from_file(Assets.ROOT + "atlas_%d.png" % int(info.atlas))
		var original := atlas.get_region(Rect2i(Assets.rect(info.region)))
		original.convert(Image.FORMAT_RGBA8)
		assert(hash_bytes(original.get_data()) == proof.rgba_sha256)
		assert(
			(
				hash_bytes(visible_bytes(Assets.texture(proof.sprite).get_image()))
				== proof.visible_rgba_sha256
			)
		)
	if DisplayServer.get_name() != "headless":
		await verify_scene(evidence)
	print("OUTLINE_ISOLATION_PASS")
	quit()


func frames(count := 3) -> void:
	for frame in count:
		await process_frame
	await RenderingServer.frame_post_draw


func capture(lab: Node, bow: Node, selected: bool) -> Image:
	bow.weakpoint_presentation.outline.set_selected(selected)
	bow.weakpoint_presentation.outline.step(float(bow.data.common.OutLineSpeed))
	await frames()
	# Compare the scene buffer before bloom: the halo can legitimately spread
	# outside the body's mesh, but unrelated source sprites must not change.
	return lab.viewport.get_texture().get_image()


func verify_scene(evidence: Dictionary) -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	var bow: Node
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		enemy.ranged_combat.target = null
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
	lab.player.position = bow.position + Vector2(90, 0) - lab.player.body_shape.position
	await frames(45)
	# Stop camera, scene clips and scripted prop motion in both comparisons.
	# Rendering stays active; the test changes only one material value at a time.
	lab.process_mode = Node.PROCESS_MODE_DISABLED
	var body: Node2D = bow.visuals[bow.data.primary_visual]
	var transform := body.get_global_transform_with_canvas()
	var flip := Vector2(-1.0 if body.data.flip[0] else 1.0, -1.0 if body.data.flip[1] else 1.0)
	var vertices: Array = body.effect_mesh.vertices
	var bounds := Rect2(transform * (Assets.vec(vertices[0]) * flip), Vector2.ZERO)
	for vertex: Array in vertices:
		bounds = bounds.expand(transform * (Assets.vec(vertex) * flip))
	bounds = bounds.grow(2.0)
	var poses: Dictionary = {}
	for pose: String in evidence:
		lab.player.sprite.play(pose, true)
		assert(lab.player.sprite.texture == Assets.texture(evidence[pose].sprite))
		var enabled := await capture(lab, bow, true)
		var disabled := await capture(lab, bow, false)
		poses[pose] = disabled
		var changed_body := 0
		var outside_error := 0.0
		for y in disabled.get_height():
			for x in disabled.get_width():
				var first := enabled.get_pixel(x, y)
				var second := disabled.get_pixel(x, y)
				var difference := maxf(
					absf(first.r - second.r),
					maxf(absf(first.g - second.g), absf(first.b - second.b))
				)
				if bounds.has_point(Vector2(x + 0.5, y + 0.5)):
					if difference > 0.002:
						changed_body += 1
				else:
					outside_error = maxf(outside_error, difference)
		print(
			"OUTLINE_ISOLATION_GPU pose=",
			pose,
			" body_pixels=",
			changed_body,
			" outside_error=",
			outside_error
		)
		assert(changed_body > 20, "The test must exercise visible enemy outline pixels")
		assert(outside_error < 0.002, "Outline toggle altered unrelated scene pixels")
		root.get_texture().get_image().save_png(
			"res://tmp/art-direction/outline_isolation_%s.png" % pose
		)
	# The red fragments belong to the distinct source spawn pose, even with the
	# enemy outline disabled. Require a substantial player-pose difference.
	var pose_changes := 0
	for y in poses.spawn.get_height():
		for x in poses.spawn.get_width():
			if not bounds.has_point(Vector2(x + 0.5, y + 0.5)):
				if poses.spawn.get_pixel(x, y) != poses.idle.get_pixel(x, y):
					pose_changes += 1
	assert(pose_changes > 20)
	print("OUTLINE_POSE_DIFFERENCE pixels=", pose_changes)
	lab.queue_free()
	await process_frame
