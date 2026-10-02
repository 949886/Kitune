extends SceneTree
## Native fence pixels: fixed borders, repeated center, partial tiles and flips.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const Slicing = preload("res://Samples/ArtDirection/Runtime/OriginalSpriteSlicing.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var info := Slicing.definition("sharedassets25_142")
	assert(Assets.vec(info.size) == Vector2(347, 31))
	assert(info.border == [20.0, 19.0, 18.0, 0.0])
	var quads := Slicing.build(info, Rect2(0, 0, 900, 37), 1.0, true)
	# Five horizontal spans and three vertical spans. The 244px final center
	# tile is cropped; the right 18px border appears once, after that tile.
	assert(quads.size() == 30)
	_verify_piece(quads, Rect2(638, 0, 244, 19), Rect2(20, 0, 244, 19))
	_verify_piece(quads, Rect2(882, 0, 18, 19), Rect2(329, 0, 18, 19))
	_verify_piece(quads, Rect2(882, 19, 18, 6), Rect2(329, 25, 18, 6))
	var stretched := Slicing.build(info, Rect2(0, 0, 900, 37), 1.0, false)
	assert(stretched.size() == 12)
	_verify_piece(stretched, Rect2(20, 0, 862, 19), Rect2(20, 0, 309, 19))
	# Trim clipping must preserve the requested geometry's transparent margins.
	var trimmed := info.duplicate(true)
	trimmed.trim = [5, 3, 332, 26]
	var clipped := Slicing.build(trimmed, Rect2(0, 0, 900, 37), 1.0, true)
	_verify_piece(clipped, Rect2(5, 3, 15, 16), Rect2(0, 0, 15, 16))
	if DisplayServer.get_name() != "headless":
		await _gpu_fence()
	print("SPRITE_SLICING_PASS")
	quit()


func _verify_piece(quads: Array[Rect2], target: Rect2, region: Rect2) -> void:
	for index in range(0, quads.size(), 2):
		if quads[index] == target:
			assert(quads[index + 1] == region)
			return
	assert(false, "Missing native border or partial tile: %s" % target)


func _gpu_fence() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(920, 60)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var visual := Visual.new()
	var item := {
		"sprite": "sharedassets25_142",
		"transform": [1, 0, 0, 1, 460, 28.5],
		"color": [1, 1, 1, 1],
		"flip": [false, false],
		"blend": "normal",
		"mode": 2,
		"size": [900, 37],
	}
	visual.configure(item)
	viewport.add_child(visual)
	var original := visual.source.get_image()
	for mirrored in [false, true]:
		visual.data.flip[0] = mirrored
		visual.queue_redraw()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var mismatches := 0
		for y in 37:
			var source_y := y if y < 19 else 30 - (36 - y) % 12
			for x in 900:
				var column := 899 - x if mirrored else x
				var source_x := column
				if column >= 882:
					source_x = 329 + column - 882
				elif column >= 20:
					source_x = 20 + (column - 20) % 309
				var expected := original.get_pixel(source_x, source_y)
				var rendered := actual.get_pixel(x + 10, y + 10)
				if absf(rendered.a - expected.a) > 0.005:
					mismatches += 1
				elif expected.a > 0.99 and not rendered.is_equal_approx(expected):
					mismatches += 1
		print("SLICE_NATIVE_PIXELS mirrored=", mirrored, " mismatches=", mismatches)
		assert(mismatches == 0, "Nine-slice rendering altered source fence pixels")
	viewport.queue_free()
	await process_frame
