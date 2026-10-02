extends SceneTree
## Verify original frames, pivots, default playback rates and cached loop timing.

const Stage = preload("res://Samples/ArtDirection/Runtime/OriginalStage.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_verify_imported_atlases()

	var factory := Stage.new()
	root.add_child(factory)
	factory.configure(Assets.ROOT + "level15.json")
	factory.animation.set_process(false)
	var bow := _find_track(factory, "Animation_Enemy_Bow_Idle")
	assert(bow.clip.frames.size() == 28 and is_equal_approx(bow.clip.speed, 0.5))
	assert(Assets.sprite_info(bow.node.current_sprite).name == "Char_Enemy_Bow_Idle_0")

	for tick in 12:
		factory.animation.advance(1.0 / 60.0)
	assert(Assets.sprite_info(bow.node.current_sprite).name == "Char_Enemy_Bow_Idle_5")
	var sprite_info := Assets.sprite_info(bow.node.current_sprite)
	assert(bow.node.destination.position == Assets.vec(sprite_info.offset))
	assert(bow.node.destination.size == Assets.vec(sprite_info.size))

	var fan := _find_track(factory, "fan_spin")
	assert(is_equal_approx(fan.node.animation_rotation, -deg_to_rad(99.0)))

	var shrine := Stage.new()
	root.add_child(shrine)
	shrine.configure(Assets.ROOT + "level25.json")
	shrine.animation.set_process(false)
	var shaman := _find_track(shrine, "Shaman Idle")
	assert(shaman.clip.source == "SimpleAnimator" and shaman.clip.frames.size() == 20)
	for tick in 12:
		shrine.animation.advance(1.0 / 60.0)
	assert(shaman.node.current_sprite == shaman.clip.frames[5][1])

	# 20 source frames / (60 fps * 0.5 speed) = 40 engine ticks per cycle.
	for tick in 28:
		shrine.animation.advance(1.0 / 60.0)
	assert(is_zero_approx(shaman.time), "Cached SimpleAnimator must reset after 40 ticks")
	shrine.animation.advance(0.0)
	assert(shaman.node.current_sprite == shaman.clip.frames[0][1])

	factory.queue_free()
	shrine.queue_free()
	await process_frame
	print("ORIGINAL_ANIMATION_PASS")
	quit()


func _find_track(stage: Node, clip_name: String) -> Dictionary:
	for track: Dictionary in stage.animation.tracks:
		if track.clip.clip == clip_name:
			return track
	assert(false, "Missing original scene animation: " + clip_name)
	return {}


func _verify_imported_atlases() -> void:
	var provenance: Dictionary = Assets.read_json(Assets.ROOT + "provenance.json")
	for index in int(provenance.atlas_count):
		var path := Assets.ROOT + "atlas_%d.png" % index
		var original := Image.new()
		assert(original.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
		var imported := (load(path) as Texture2D).get_image()
		if imported.is_compressed():
			imported.decompress()
		original.convert(Image.FORMAT_RGBA8)
		imported.convert(Image.FORMAT_RGBA8)
		# Godot fills RGB beneath transparent borders during the lossless import.
		var options := ConfigFile.new()
		assert(options.load(path + ".import") == OK)
		if options.get_value("params", "process/fix_alpha_border", true):
			original.fix_alpha_edges()
		assert(original.get_data() == imported.get_data(), "Stale Godot atlas import: " + path)
