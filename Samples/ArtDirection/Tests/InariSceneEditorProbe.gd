extends SceneTree
## Run with --editor: static native sprites must be visible without running
## gameplay initialization or constructing another world from the source JSON.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	assert(Engine.is_editor_hint(), "Run this probe with --headless --editor")
	var checked := 0
	for profile: Dictionary in Assets.read_json("res://Samples/ArtDirection/Profiles/levels.json"):
		if profile.kind != "original_2d":
			continue
		var packed: PackedScene = load(profile.stage_scene)
		var stage := packed.instantiate()
		root.add_child(stage)
		var count := 0
		for visual: Node in stage.find_children("*", "Node2D", true, false):
			if not visual.has_method("prepare") or visual.source_item.sprite == null:
				continue
			assert(visual.source != null and visual.current_sprite == visual.source_item.sprite)
			assert(not visual.is_processing(), "Editor preview must not animate the saved pose")
			count += 1
		assert(count > 0)
		print("INARI_SCENE_EDITOR ", profile.id, " sprites=", count)
		stage.free()
		checked += 1
	assert(checked == 2)
	print("INARI_SCENE_EDITOR_PASS")
	quit()
