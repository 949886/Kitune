extends SceneTree
## Exercise the real lab selectors and round-trip every gameplay pose. Returning
## to Shiro must discard replacement atlases and restore both transform axes.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	assert(lab.initial_character == "shiro")
	assert(lab.characters[lab.selected_character].id == "shiro")
	assert(lab.character_selectors.size() == 2)
	var shiro: int = lab.selected_character
	var replacement := -1
	for index in lab.characters.size():
		if lab.characters[index].id == "white_sailor":
			replacement = index
	assert(replacement >= 0)
	# Choosing in the gallery affects the next actor, without entering a level.
	lab.character_selectors[1].item_selected.emit(replacement)
	assert(lab.selected == -1 and lab.gallery.visible)
	for selector: OptionButton in lab.character_selectors:
		assert(selector.selected == replacement)
	lab.load_level(1)
	lab.set_controls_enabled(false)
	var actor: Node = lab.player
	var stage: Node = lab.stage
	var camera: Node = lab.camera_rig
	var sprite: Sprite2D = actor.sprite
	var path: String = lab.characters[replacement].appearance_path
	assert(actor.appearance_path == path)
	assert(not sprite.appearance.profile.is_empty())
	# Frozen comparison views must still update immediately when a skin changes.
	lab.reference_mode = true
	actor.position += Vector2(15, -20)
	actor.velocity = Vector2(35, -10)
	actor.stamina *= 0.5
	actor.checkpoint_source = "character-selection-probe"
	lab.objective_index = 1
	var position: Vector2 = actor.position
	var velocity: Vector2 = actor.velocity
	var stamina: float = actor.stamina
	var checkpoint: Vector2 = actor.checkpoint
	var material: Material = sprite.material
	for name: String in sprite.clips:
		sprite.play(name, true)
		sprite.elapsed = float(sprite.clips[name].length) * 0.37
		sprite.body_rotation = PI / 2.0
		sprite.gfx_rotation = -0.3
		for facing in [-1.0, 1.0]:
			sprite.facing = facing
			lab.character_selectors[0].item_selected.emit(shiro)
			var texture: Texture2D = sprite.texture
			var transform: Transform2D = sprite.transform
			var elapsed: float = sprite.elapsed
			assert(sprite.scale.is_equal_approx(Vector2(facing, 1.0)))
			lab.character_selectors[0].item_selected.emit(replacement)
			assert((sprite.texture as AtlasTexture).atlas.resource_path.contains("WhiteSailor/"))
			assert(sprite.clip_name == name and sprite.elapsed == elapsed)
			lab.character_selectors[0].item_selected.emit(shiro)
			assert(sprite.texture == texture and sprite.transform.is_equal_approx(transform))
			assert(sprite.appearance.profile.is_empty() and sprite.appearance.textures.is_empty())
			assert(sprite.appearance.manifest.is_empty() and sprite.appearance.directory.is_empty())
			assert(sprite.material == material)
			lab.water_capture._process(0.0)
			var reflection: Sprite2D = lab.water_capture.actor_pairs[0].copy
			assert(reflection.texture == sprite.texture)
			assert(reflection.transform.is_equal_approx(sprite.global_transform))
	assert(lab.player == actor and lab.stage == stage and lab.camera_rig == camera)
	assert(actor.position == position and actor.velocity == velocity)
	assert(actor.stamina == stamina and actor.checkpoint == checkpoint)
	assert(actor.checkpoint_source == "character-selection-probe")
	assert(lab.objective_index == 1 and lab.reference_mode and not lab.controls_enabled)
	# An invalid option must leave the current choice and actor intact.
	lab.select_character(-1)
	lab.select_character(lab.characters.size())
	assert(lab.selected_character == shiro and lab.player == actor)
	lab.select_character(replacement)
	lab.show_gallery()
	lab.load_level(0)
	assert(lab.player.appearance_path == path)
	lab.load_level(2, 1)
	assert(lab.practice_entry == 1 and lab.player.appearance_path == path)
	lab.respawn_player()
	assert(lab.player.appearance_path == path)
	lab.select_character(shiro)
	lab.load_level(2, 0)
	assert(lab.player.appearance_path.is_empty())
	assert(lab.player.sprite.appearance.profile.is_empty())
	# Popup interaction pauses the gameplay input; closing while comparing must
	# not unpause the actor, and closing in gameplay must restore input.
	lab.reference_mode = true
	var popup: PopupMenu = lab.character_selectors[0].get_popup()
	popup.about_to_popup.emit()
	assert(lab.character_menu_open and not lab.controls_enabled)
	popup.popup_hide.emit()
	for frame in range(3):
		await process_frame
	assert(not lab.character_menu_open and not lab.controls_enabled)
	lab.reference_mode = false
	popup.about_to_popup.emit()
	popup.popup_hide.emit()
	for frame in range(3):
		await process_frame
	assert(lab.controls_enabled)
	for selector: OptionButton in lab.character_selectors:
		assert(selector.selected == shiro)
	print("CHARACTER_SELECTION_PASS")
	lab.queue_free()
	await process_frame
	quit()
