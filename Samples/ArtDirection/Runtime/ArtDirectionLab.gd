extends Node
## Playable INARI studies; screenshot comparison is offered where a reference exists.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const OriginalStage = preload("res://Samples/ArtDirection/Runtime/OriginalStage.gd")
const InariPlayer = preload("res://Samples/ArtDirection/Runtime/InariStudyPlayer.gd")
const InariCameraRig = preload("res://Samples/ArtDirection/Runtime/InariCameraRig.gd")
const Bloom = preload("res://Samples/ArtDirection/Runtime/OriginalBloom.gd")
const WaterCapture = preload("res://Samples/ArtDirection/Runtime/OriginalWaterCapture.gd")
const EnvironmentAudio = preload("res://Samples/INARIMechanisms/Devices/EnvironmentAudio/EnvironmentAudio.tscn")
const EnvironmentZones = preload("res://Samples/ArtDirection/Runtime/InariEnvironmentAudioZones.gd")
const ShurikenDistanceZones = preload("res://Samples/ArtDirection/Runtime/InariShurikenDistanceZones.gd")
const PROFILE_PATH := "res://Samples/ArtDirection/Profiles/levels.json"
const CHARACTER_PROFILE_PATH := "res://Samples/ArtDirection/Profiles/characters.json"
const REFERENCE_ROOT := "res://Samples/ArtDirection/References/"

@export var initial_level := ""
@export var story_mode := false
## Stable ID from characters.json; the same choice follows every level and portal.
@export var initial_character := "shiro"

var characters: Array
var selected_character := -1
var character_selectors: Array[OptionButton] = []
var character_menu_open := false

# The active level owns its actor, camera and physics world.
var profiles: Array
var active_profile: Dictionary
var practice_entry := 0
var practice_selector := HBoxContainer.new()
var interaction_hint := Label.new()
var transition_cover := ColorRect.new()
var transition_target: Dictionary = {}
var transition_time := 0.0
var transition_phase := ""
var transition_duration := 0.0
var last_scene_transition: Dictionary = {}
var selected := -1
var viewport: SubViewport
var player: CharacterBody2D
var stage: Node2D
var camera: Camera2D
var camera_rig: Node
var bloom: Node
var water_capture: Node
var environment_audio: Node
var environment_zones: Node

# UI persists across level switches and renders outside the game viewport.
var ui := CanvasLayer.new()
var screen := Control.new()
var game_view := TextureRect.new()
var reference_view := TextureRect.new()
var gallery := Control.new()
var status: Label
var detail: Label
var progress: Label
var completion := PanelContainer.new()
var hud := Control.new()
var controls: Label

var objective_index := 0
var reference_mode := false
var hud_visible := true
var completed := false
var controls_enabled := true
var trial_sessions: Dictionary = {}


func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	profiles = Assets.read_json(PROFILE_PATH)
	characters = Assets.read_json(CHARACTER_PROFILE_PATH)
	assert(not characters.is_empty(), "The lab needs at least one character")
	selected_character = 0
	for index in characters.size():
		if characters[index].id == initial_character:
			selected_character = index
			break

	# Game rendering and the original reference use separate views in the same UI.
	add_child(ui)
	ui.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	screen.add_child(game_view)
	game_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	game_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	game_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	screen.add_child(reference_view)
	reference_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reference_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reference_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reference_view.visible = false

	screen.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud()
	_build_gallery()
	screen.add_child(transition_cover)
	transition_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_cover.color = Color.BLACK
	transition_cover.hide()

	# Scene wrappers and CLI launches both resolve through the profile's stable ID.
	for i in profiles.size():
		if profiles[i].id == initial_level:
			load_level(i)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			for i in profiles.size():
				if profiles[i].id == arg.trim_prefix("level="):
					load_level(i)


func _label(parent: Node, text: String, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	parent.add_child(label)

	return label


func _build_hud() -> void:
	_build_character_selector(hud, Vector2(1000, 100))
	hud.add_child(interaction_hint)
	interaction_hint.position = Vector2(26, 90)
	interaction_hint.add_theme_font_size_override("font_size", 20)
	hud.add_child(practice_selector)
	practice_selector.position = Vector2(26, 53)
	practice_selector.add_theme_constant_override("separation", 10)
	var bottom := ColorRect.new()
	bottom.color = Color(0.025, 0.032, 0.045, 0.92)
	bottom.position = Vector2(0, 650)
	bottom.size = Vector2(1280, 70)
	hud.add_child(bottom)

	status = _label(hud, "", Vector2(26, 660), 19)
	detail = _label(hud, "", Vector2(26, 688), 12, Color(0.7, 0.75, 0.8))
	progress = _label(hud, "", Vector2(840, 665), 14, Color(0.9, 0.81, 0.6))

	controls = _label(hud, "", Vector2(26, 20), 14)
	controls.add_theme_color_override("font_shadow_color", Color.BLACK)
	controls.add_theme_constant_override("shadow_offset_x", 1)
	controls.add_theme_constant_override("shadow_offset_y", 2)

	_build_completion_panel()


func _build_character_selector(parent: Control, position: Vector2) -> void:
	var row := HBoxContainer.new()
	row.position = position
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = "角色"
	row.add_child(label)
	var selector := OptionButton.new()
	selector.name = "CharacterSelector"
	selector.custom_minimum_size.x = 190
	# Releasing keyboard focus keeps Space and the gameplay shortcuts available.
	selector.focus_mode = Control.FOCUS_NONE
	for character: Dictionary in characters:
		selector.add_item(character.name)
	selector.select(selected_character)
	selector.item_selected.connect(select_character)
	selector.get_popup().about_to_popup.connect(_open_character_menu)
	selector.get_popup().popup_hide.connect(_close_character_menu)
	row.add_child(selector)
	character_selectors.append(selector)


func select_character(index: int) -> void:
	if index < 0 or index >= characters.size():
		return
	selected_character = index
	for selector: OptionButton in character_selectors:
		selector.select(index)
	if is_instance_valid(player):
		# Change drawings in place: checkpoints, combat clocks, camera bindings and
		# scene mechanisms continue using the existing actor and world.
		player.set_appearance(characters[index].appearance_path)


func _open_character_menu() -> void:
	character_menu_open = true
	if is_instance_valid(player):
		set_controls_enabled(false)


func _close_character_menu() -> void:
	character_menu_open = false
	# The controller polls global Input. Let the UI click expire before resuming
	# so opening/selecting a skin cannot also attack or throw a projectile.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(player) and not character_menu_open:
		set_controls_enabled(
			not gallery.visible and not reference_mode and transition_phase.is_empty()
		)


func _build_completion_panel() -> void:
	completion.position = Vector2(390, 225)
	completion.size = Vector2(500, 220)
	hud.add_child(completion)
	var box := VBoxContainer.new()
	completion.add_child(box)

	var label := Label.new()
	label.text = "路线完成\n可继续探索，或返回选择其他关卡。"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	box.add_child(label)

	var again := Button.new()
	again.text = "重新体验"
	again.pressed.connect(func(): load_level(selected, practice_entry))
	box.add_child(again)

	var back := Button.new()
	back.text = "返回关卡选择"
	back.pressed.connect(show_gallery)
	box.add_child(back)
	completion.hide()


func _build_gallery() -> void:
	screen.add_child(gallery)
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color("0b0f16")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gallery.add_child(background)

	_label(gallery, "ROSSI  /  VISUAL STUDIES", Vector2(36, 23), 14, Color("b9a67b"))
	_label(gallery, "INARI · 原版视觉对照", Vector2(34, 53), 34)
	_label(gallery, "原版场景 · 角色操作 · 机关联动", Vector2(36, 104), 15, Color("a9b2be"))
	_build_character_selector(gallery, Vector2(1000, 75))
	var columns := mini(3, profiles.size())
	var card_width := (1208.0 - 24.0 * (columns - 1)) / columns
	for i in profiles.size():
		var profile: Dictionary = profiles[i]
		var column := i % columns
		var row := i / columns
		var position := Vector2(36 + column * (card_width + 24.0), 186 + row * 394)

		var button := Button.new()
		button.position = position
		button.size = Vector2(card_width, 366)
		button.tooltip_text = profile.fidelity
		button.pressed.connect(load_level.bind(i))
		gallery.add_child(button)

		var image := TextureRect.new()
		var preview: String = profile.get(
			"preview", REFERENCE_ROOT + str(profile.get("reference", ""))
		)
		if ResourceLoader.exists(preview):
			image.texture = load(preview)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.position = Vector2(7, 7)
		image.size = Vector2(card_width - 14.0, 286)
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(image)

		_label(button, "%d  %s" % [i + 1, profile.game], Vector2(14, 303), 13, Color("cbbb98"))
		_label(button, profile.title, Vector2(14, 329), 18)
	var devices := Button.new()
	devices.position = Vector2(36, 584)
	devices.size = Vector2(1208, 58)
	devices.text = "可复用装置展厅"
	devices.pressed.connect(_open_device_showcase)
	gallery.add_child(devices)
	_label(
		gallery,
		"关卡、角色与素材说明见右侧。  ·  数字 1–%d 快速进入" % profiles.size(),
		Vector2(36, 689),
		12,
		Color("7e8b9a")
	)
	hud.hide()


func _open_device_showcase() -> void:
	var window := Window.new()
	window.title = "INARI · 可复用装置"
	window.size = Vector2i(1280, 720)
	window.world_2d = World2D.new()
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var exhibit: PackedScene = load("res://Samples/INARIMechanisms/Examples/DeviceGallery.tscn")
	window.add_child(exhibit.instantiate())
	window.popup_centered()


func load_level(index: int, entry_index := 0) -> void:
	# Removed or unavailable entries must never index beyond the profile list.
	if index < 0 or index >= profiles.size():
		return
	transition_target.clear()
	transition_phase = ""
	transition_cover.hide()
	last_scene_transition.clear()
	selected = index
	objective_index = 0
	completed = false
	controls_enabled = true
	hud_visible = true
	reference_mode = false

	completion.hide()
	reference_view.hide()
	gallery.hide()
	hud.show()

	var profile: Dictionary = profiles[index]
	practice_entry = entry_index
	if profile.has("practice_entries"):
		assert(entry_index >= 0 and entry_index < profile.practice_entries.size())
		profile = profile.duplicate(true)
		profile.merge(profile.practice_entries[entry_index], true)
	active_profile = profile
	for child: Node in practice_selector.get_children():
		practice_selector.remove_child(child)
		child.queue_free()
	for entry in profile.get("practice_entries", []).size():
		var button := Button.new()
		button.text = profile.practice_entries[entry].label
		button.disabled = entry == entry_index
		button.pressed.connect(load_level.bind(index, entry))
		practice_selector.add_child(button)
	_replace_scene(profile)


func _replace_scene(profile: Dictionary) -> void:
	active_profile = profile
	_create_viewport(profile)
	_create_stage(profile)
	_add_letterbox(profile)
	_create_actor(profile)
	_set_level_text(profile)
	_update_progress()
	stage.scene_change_requested.connect(_begin_scene_transition, CONNECT_DEFERRED)
	if is_instance_valid(stage.machinery.arrival):
		stage.machinery.arrival.finished.connect(_on_arrival_complete)


func _begin_scene_transition(record: Dictionary) -> void:
	if not transition_target.is_empty():
		return
	transition_target = record
	transition_time = 0.0
	transition_phase = "out"
	transition_duration = float(
		Assets.read_json(Assets.ROOT + "machinery.json").scene_rules.fade_duration
	)
	transition_cover.modulate.a = 0.0
	transition_cover.show()
	set_controls_enabled(false)


func _process(delta: float) -> void:
	if transition_phase.is_empty():
		return
	transition_time += delta
	var fraction := clampf(transition_time / transition_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - fraction, 2.0)
	transition_cover.modulate.a = eased if transition_phase == "out" else 1.0 - eased
	if fraction < 1.0:
		return
	if transition_phase == "out":
		var next := active_profile.duplicate(true)
		next.erase("stage_scene")
		next.scene_data = transition_target.destination
		var data: Dictionary = Assets.read_json(Assets.ROOT + next.scene_data)
		# SceneRoot's spawn uses the native player origin; the study actor uses
		# its feet. Native OnAfterSceneChanged restores StoryModeHp; the new
		# actor already starts at that configured maximum. Stamina persists.
		var origin_offset := Vector2(
			-float(player.tuning.body_offset.x) * player.units,
			-player.body_size.y / 2.0 + float(player.tuning.body_offset.y) * player.units
		)
		var spawn := Assets.vec(data.spawn) - origin_offset
		next.spawn = [spawn.x, spawn.y]
		next.checkpoints = [next.spawn]
		var stamina: float = player.stamina
		last_scene_transition = {
			"from": stage.data.source, "to": data.source, "go": transition_target.go
		}
		_replace_scene(next)
		player.stamina = stamina
		player.health_changed.emit(player.damage.health, player.damage.maximum)
		set_controls_enabled(false)
		# Destination Timeline starts while the native loading cover fades out.
		if is_instance_valid(stage.machinery.arrival):
			stage.process_mode = Node.PROCESS_MODE_INHERIT
		transition_phase = "in"
		transition_time = 0.0
	else:
		transition_phase = ""
		transition_target = {}
		transition_cover.hide()
		set_controls_enabled(true)
		if not is_instance_valid(stage.machinery.arrival) or not stage.machinery.arrival.active:
			_on_arrival_complete()


func _on_arrival_complete() -> void:
	completed = true
	controls_enabled = true
	completion.show()
	_update_progress()


func _create_viewport(profile: Dictionary) -> void:
	water_capture = null
	if is_instance_valid(stage) and is_instance_valid(stage.machinery) and is_instance_valid(stage.machinery.repeating):
		stage.machinery.repeating.before_scene_changed()
	# Each level owns its physics and rendering worlds; switching frees the old one.
	if is_instance_valid(bloom):
		# Bloom owns the nested rendering chain and its original scene viewport.
		remove_child(bloom)
		bloom.queue_free()
		viewport = null
		bloom = null
	elif is_instance_valid(viewport):
		remove_child(viewport)
		viewport.queue_free()

	viewport = SubViewport.new()
	game_view.material = null
	viewport.size = Vector2i(Assets.vec(profile.get("viewport_size", [640, 360])))
	if not profile.has("viewport_size"):
		# The shipped main camera has no low-resolution target and uses renderScale=1.
		# Rasterize at the comparison image size; camera framing remains in world units.
		var reference: Texture2D = load(REFERENCE_ROOT + profile.reference)
		viewport.size = Vector2i(reference.get_size())
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	game_view.texture = viewport.get_texture()

	game_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _create_stage(profile: Dictionary) -> void:
	stage = (
		(load(profile.stage_scene) as PackedScene).instantiate()
		if profile.has("stage_scene")
		else OriginalStage.new()
	)
	viewport.add_child(stage)
	stage.configure(Assets.ROOT + profile.scene_data, profile)
	stage.chromatic.bind_material(stage.lighting.exposure_material)
	game_view.material = stage.lighting.display_material(get_viewport())
	if viewport.use_hdr_2d and stage.lighting.settings.bloom.active:
		bloom = Bloom.new()
		add_child(bloom)
		var exposure: float = stage.lighting.exposure_material.get_shader_parameter(
			"exposure_stops"
		)
		stage.lighting.exposure_screen.hide()
		bloom.configure(viewport, stage.lighting.settings.bloom, get_viewport(), exposure)
		game_view.material = bloom.presentation
		stage.chromatic.bind_material(bloom.presentation)


func _add_letterbox(profile: Dictionary) -> void:
	var ratio := float(profile.get("letterbox_ratio", 0.0))
	assert(ratio >= 0.0 and ratio < 0.5)
	if is_instance_valid(bloom):
		bloom.presentation.set_shader_parameter("letterbox", ratio)
		return

	if ratio > 0.0:
		var bars := CanvasLayer.new()
		bars.name = "Letterbox"
		bars.layer = 2
		viewport.add_child(bars)
		var height := float(viewport.size.y) * ratio
		for y in [0.0, float(viewport.size.y) - height]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.position = Vector2(0, y)
			bar.size = Vector2(viewport.size.x, height)
			bars.add_child(bar)


func _create_actor(profile: Dictionary) -> void:
	player = InariPlayer.new()
	player.z_index = 400
	player.position = Assets.vec(profile.spawn)
	player.audio_surface = profile.get("audio_surface", "metal")
	player.appearance_path = characters[selected_character].appearance_path
	player.story_mode = story_mode

	# The study's terrain uses layer 1 and hazards detect layer 2.
	player.collision_layer = 2
	player.collision_mask = 1
	viewport.add_child(player)
	if not stage.player_idle.is_empty():
		player.sprite.clips[stage.player_idle.name] = stage.player_idle
		player.idle_clip = stage.player_idle.name
		var pose: Dictionary = stage.player_idle.pose
		if not profile.has("stage_scene"):
			player.position = Assets.vec(pose.root_position) - player.body_shape.position
		player.facing = pose.facing
	player.z_index = stage.sort_depth(player.tuning.sprite_sort)
	player.sprite.apply_material(player.sprite, stage.lighting)
	player.projectile.apply_material(player.projectile, stage.lighting)
	player.projectile.z_index = stage.sort_depth(player.projectile.renderer.sort)
	player.targeting.enemies = stage.enemies
	player.targeting.configure_presentation(stage)
	player.weak_dash.configure(player, stage)
	player.wind_trail.advance()
	stage.combat_clock.subscribe(player)
	for enemy: Node in stage.enemies:
		stage.combat_clock.subscribe(enemy)
		enemy.ranged_combat.target = player

	set_checkpoint(player.position)
	if profile.get("enable_trial", false):
		if not trial_sessions.has(stage.data.source):
			trial_sessions[stage.data.source] = {}
		stage.scene_options.trial_session = trial_sessions[stage.data.source]
	stage.bind_source_mechanisms(player)
	if is_instance_valid(stage.machinery.battle):
		for trigger: Area2D in stage.machinery.battle.spawn_contacts:
			trigger.is_loading = func(): return not transition_phase.is_empty()
	if profile.get("enable_battle", false):
		player.respawned.connect(_restart_battle, CONNECT_DEFERRED)
	for checkpoint: Area2D in stage.source_checkpoints:
		checkpoint.saved.connect(_on_source_checkpoint)

	if profile.has("stage_scene"):
		camera_rig = stage.authored_camera
	else:
		camera_rig = InariCameraRig.new()
		viewport.add_child(camera_rig)
	camera_rig.configure_2d(profile, player, stage.source_camera)
	stage.bind_camera_zones(player, camera_rig, func(): return not transition_phase.is_empty())
	if not is_instance_valid(environment_audio):
		environment_audio = EnvironmentAudio.instantiate()
		add_child(environment_audio)
	environment_zones = EnvironmentZones.new()
	stage.add_child(environment_zones)
	environment_zones.configure(stage, player, environment_audio, func(): return not transition_phase.is_empty())
	var range_zones := ShurikenDistanceZones.new()
	stage.add_child(range_zones)
	range_zones.configure(stage, player, func(): return not transition_phase.is_empty())
	if is_instance_valid(stage.machinery.trial):
		stage.machinery.trial.rig = camera_rig
	camera = camera_rig.camera_2d
	stage.projection.attach_camera(camera)
	for visual: Node2D in stage.visual_instances:
		if visual.is_water:
			water_capture = WaterCapture.new()
			viewport.add_child(water_capture)
			water_capture.configure(stage, player, camera)
			break


func _set_level_text(profile: Dictionary) -> void:
	reference_view.texture = (
		load(REFERENCE_ROOT + profile.reference) if profile.has("reference") else null
	)
	status.text = profile.game + "   /   " + profile.title
	detail.text = profile.fidelity

	controls.text = "AD 移动 / WS 攀爬   空格 跳跃   Shift 冲刺   左键 攻击   E 重击   右键 投掷   Q 瞬移   R 重试   Tab 原图   H 隐藏   Esc 选关"
	if not profile.has("reference"):
		controls.text = controls.text.replace("   Tab 原图", "")


func _physics_process(_delta: float) -> void:
	if selected < 0 or gallery.visible or not is_instance_valid(player):
		return

	var profile: Dictionary = active_profile
	if reference_mode:
		return
	interaction_hint.text = (
		player.interaction_target.prompt if is_instance_valid(player.interaction_target) else ""
	)
	if interaction_hint.text.is_empty() and is_instance_valid(stage.machinery.trial):
		interaction_hint.text = stage.machinery.trial.status_text()
	if interaction_hint.text.is_empty() and is_instance_valid(stage.machinery.battle):
		interaction_hint.text = stage.machinery.battle.status_text()

	if player.position.y > get_checkpoint().y + 1800:
		respawn_player()

	_check_route_progress(profile)


func _check_route_progress(profile: Dictionary) -> void:
	if not completed:
		var objective: Dictionary = profile.objectives[objective_index]
		var pose_ready := true
		if objective.has("condition"):
			pose_ready = stage.machinery.satisfies(objective.condition)
		if objective.get("grounded", false):
			pose_ready = pose_ready and player.is_on_floor()
		if objective.get("climbing", false):
			pose_ready = pose_ready and player.climbing
		if (
			pose_ready
			and (
				player.position.distance_to(Assets.vec(objective.position))
				< float(objective.radius)
			)
		):
			objective_index += 1
			if objective_index >= profile.objectives.size():
				completed = true
				completion.show()
			_update_progress()

	# Once a source save is reached, route-assistance markers cannot silently
	# replace the original respawn location or its stored direction.
	if not player.checkpoint_source.is_empty():
		return
	for point: Array in profile.get("checkpoints", []):
		var checkpoint := Assets.vec(point)
		if player.position.distance_to(checkpoint) < 50 and get_checkpoint() != checkpoint:
			set_checkpoint(checkpoint)


func get_checkpoint() -> Vector2:
	return player.checkpoint


func set_checkpoint(point: Vector2) -> void:
	player.checkpoint = point
	player.checkpoint_facing = 0.0
	player.checkpoint_source = ""


func _on_source_checkpoint(_checkpoint: Area2D) -> void:
	status.text = profiles[selected].title + "   /   已保存检查点 · R 返回"


func respawn_player() -> void:
	player.respawn()
	if is_instance_valid(camera_rig):
		camera_rig.warp_to_target()


func _restart_battle() -> void:
	# The practice entrance is outside a one-use closing gate. Retry the whole
	# encounter so dying cannot strand the player behind the consumed trigger.
	if active_profile.get("enable_battle", false):
		load_level(selected, practice_entry)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	# Pause the actor and its children while comparing the original image.
	player.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	stage.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if enabled and is_instance_valid(stage.machinery.arrival) and stage.machinery.arrival.active:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		controls_enabled = false
	if (
		enabled
		and is_instance_valid(stage.machinery.trial)
		and stage.machinery.trial.state == "preview"
	):
		player.process_mode = Node.PROCESS_MODE_DISABLED
		controls_enabled = false


func _update_progress() -> void:
	var profile: Dictionary = active_profile
	progress.text = (
		"路线完成  ✓"
		if completed
		else (
			"%d / %d   %s"
			% [
				objective_index + 1,
				profile.objectives.size(),
				profile.objectives[objective_index].name
			]
		)
	)


func show_gallery() -> void:
	gallery.show()
	hud.hide()
	reference_view.hide()
	if is_instance_valid(player):
		set_controls_enabled(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not transition_phase.is_empty():
		return
	if not event.is_pressed() or event.is_echo():
		return
	if not event is InputEventKey:
		return
	if event.keycode >= KEY_1 and event.keycode < KEY_1 + profiles.size():
		load_level(event.keycode - KEY_1)
	elif event.keycode == KEY_ESCAPE:
		show_gallery()
	elif selected >= 0 and not gallery.visible:
		match event.keycode:
			KEY_R:
				respawn_player()
			KEY_H:
				hud_visible = not hud_visible
				hud.visible = hud_visible
			KEY_TAB:
				if not profiles[selected].has("reference"):
					return
				reference_mode = not reference_mode
				reference_view.visible = reference_mode
				set_controls_enabled(not reference_mode)
				status.text = (
					"官方原图 · " + profiles[selected].game
					if reference_mode
					else profiles[selected].game + "   /   " + profiles[selected].title
				)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(viewport) or gallery.visible or character_menu_open:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var forwarded: InputEvent = event.duplicate()
		# TextureRect preserves aspect ratio. Account for its margins when aiming
		# after resizing the game window, rather than stretching mouse coordinates.
		var texture_size := Vector2(viewport.size)
		var ratio := minf(game_view.size.x / texture_size.x, game_view.size.y / texture_size.y)
		var margin := (game_view.size - texture_size * ratio) / 2.0
		forwarded.position = (event.position - game_view.global_position - margin) / ratio
		forwarded.global_position = forwarded.position
		viewport.push_input(forwarded, true)
	elif (
		event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	):
		# The standalone SubViewport also needs device events for native target snap.
		viewport.push_input(event, true)
