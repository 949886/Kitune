extends SceneTree
## Exercises actual FMOD instances and Godot overlaps inside a renamed package.
const Mixer = preload("../Devices/EnvironmentAudio/EnvironmentAudio.tscn")
const Zone = preload("../Devices/EnvironmentAudio/AudioParameterZone.gd")
const Gallery = preload("../Examples/DeviceGallery.tscn")
var base: String = get_script().resource_path.get_base_dir() + "/.."
var loading := false


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func actor() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(2, 2)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector2(-10000, -10000)
	return body


func run() -> void:
	root.size = Vector2i(1280, 720)
	var mixer := Mixer.instantiate()
	mixer.capture_path = ProjectSettings.globalize_path("res://environment-validation.wav")
	root.add_child(mixer)
	mixer.set_process(false)
	assert(mixer.initialized and mixer.failures.is_empty())
	assert(int(mixer._command("count")) == 3)
	mixer.reset_ambience_and_reverb()
	mixer.render_frames(48000)
	mixer.apply_zone("ambient", "", {"Radiance_Out_4": 1.0})
	mixer.render_frames(48000 * 4)
	assert(mixer.parameter("ambient", "Radiance_Out_4").is_equal_approx(Vector2.ONE))
	var preset: Resource = load(base + "/Devices/EnvironmentAudio/Presets/level15_11102.tres")
	mixer.change_bgm(preset.event_guid, preset.parameters)
	var handle: int = mixer.handles.bgm
	mixer.render_frames(48000)
	var position_before := int(mixer._command("position", str(handle)))
	mixer.change_bgm(preset.event_guid, {})
	assert(mixer.handles.bgm == handle and mixer.bgm_starts == 1)
	mixer.render_frames(48000)
	assert(int(mixer._command("position", str(handle))) > position_before)
	mixer.change_bgm("", {})
	assert(mixer.handles.bgm == handle)
	mixer.change_bgm(preset.event_guid, null)
	for key: String in mixer.document.events[preset.event_guid].parameters:
		assert(is_equal_approx(mixer.parameter("bgm", key).x, 1.0))
	mixer.enter_menu()
	assert(mixer.bgm_starts == 2 and mixer.handles.bgm != handle)
	assert(int(mixer._command("count")) == 4)
	assert(is_zero_approx(mixer.parameter("ambient", "Radiance_Out_4").x))
	var total := 0
	var inactive := 0
	var no_layer := 0
	var assignments := 0
	for scene: String in mixer.document.levels:
		for row: Dictionary in mixer.document.levels[scene]:
			var fixture := Node2D.new()
			fixture.position = Vector2(123, -85)
			fixture.rotation = 0.3
			root.add_child(fixture)
			var player := actor()
			fixture.add_child(player)
			var zone := Zone.new()
			zone.settings = load(base + "/Devices/EnvironmentAudio/Presets/%s_%s.tres" % [scene, str(int(row.source.component_id))])
			assert(zone.settings.parameters == row.parameters)
			assert(zone.settings.event_guid == row.resolved_event_guid)
			assert(zone.settings.once == bool(row.fields.once))
			assert(zone.settings.source_layer_bits == int(row.fields.triggerLayer.m_Bits))
			var box: Dictionary = row.source.colliders[0].data
			assert(zone.settings.trigger_size.is_equal_approx(Vector2(box.m_Size.x, box.m_Size.y) * 16))
			assert(zone.settings.trigger_offset.is_equal_approx(Vector2(box.m_Offset.x, -box.m_Offset.y) * 16))
			zone.transform = zone.settings.source_transform
			zone.position = Vector2.ZERO
			zone.bind_actor(player)
			zone.bind_audio(mixer)
			fixture.add_child(zone)
			player.global_position = zone.to_global(zone.settings.trigger_offset)
			await frames(4)
			if not zone.settings.initially_active:
				inactive += 1
				assert(zone.calls == 0)
				zone.activate()
				await frames(4)
			if zone.settings.source_layer_bits == 0:
				no_layer += 1
				assert(zone.calls == 0)
				zone.interactive_shuriken()
			assert(zone.calls > 0)
			if zone.settings.once:
				assert(not zone.active and not zone.save_data()[zone.settings.persistence_id + "_isActive"])
			for key: String in zone.settings.parameters:
				assert(absf(mixer.parameter(zone.settings.family, key).x - float(zone.settings.parameters[key])) < 0.00001)
				assignments += 1
			var calls: int = zone.calls
			await frames(3)
			assert(zone.calls == calls) # No Stay writes.
			player.position = Vector2(-10000, -10000)
			await frames(3)
			assert(zone.calls == calls) # Exit preserves parameters.
			for key: String in zone.settings.parameters:
				assert(absf(mixer.parameter(zone.settings.family, key).x - float(zone.settings.parameters[key])) < 0.00001)
			fixture.queue_free()
			await frames(1)
			total += 1
	assert(total == 224 and inactive == 9 and no_layer == 2 and assignments == 2760)
	await once_and_loading(mixer)
	assert(mixer.failures.is_empty())
	var native_ref: WeakRef = weakref(mixer.native)
	mixer.close()
	assert(native_ref.get_ref() == null)
	mixer.queue_free()
	await frames(2)
	await workshop()
	print("PORTABLE_ENVIRONMENT_AUDIO_PASS presets=224 assignments=2760")
	quit()


func once_and_loading(mixer: Node) -> void:
	var zone := Zone.new()
	zone.settings = load(base + "/Devices/EnvironmentAudio/Presets/level14_10743.tres").duplicate(true)
	zone.settings.once = true # Exercise configurable base behavior; source presets remain untouched.
	zone.bind_actor(null, func(): return loading)
	zone.bind_audio(mixer)
	root.add_child(zone)
	loading = true
	zone.interactive_shuriken()
	assert(zone.active and zone.calls == 1 and zone.save_data() == null)
	loading = false
	zone.interactive_shuriken()
	await frames(2)
	assert(not zone.active and zone.shape.disabled)
	zone.load_data({zone.settings.persistence_id + "_isActive": "true"})
	await frames(2)
	assert(not zone.active and zone.shape.disabled)
	var record: Dictionary = zone.save_data()
	assert(record[zone.settings.persistence_id + "_isActive"] == false)
	assert(zone.save_data() == null)
	zone.activate()
	await frames(2)
	assert(zone.active and not zone.shape.disabled and zone.save_data() == null)
	zone.load_data(record)
	await frames(2)
	assert(not zone.active and zone.shape.disabled)
	zone.interactive_shuriken()
	assert(zone.calls == 3)
	zone.queue_free()
	await frames(2)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func workshop() -> void:
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.select_exhibit(17)
	await frames(5)
	var room: Node = gallery.exhibit
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	assert(room.zones[0].calls > 0 and room.audio.bgm_starts == 1)
	key(KEY_D, true)
	await frames(120)
	key(KEY_D, false)
	assert(room.zones[3].calls > 0 and room.audio.bgm_starts == 1)
	assert(room.audio.failures.is_empty())
	var old_audio: WeakRef = weakref(room.audio.native)
	key(KEY_R, true)
	key(KEY_R, false)
	await frames(5)
	assert(gallery.exhibit != room and old_audio.get_ref() == null)
	old_audio = weakref(gallery.exhibit.audio.native)
	gallery.select_exhibit(0)
	await frames(3)
	assert(old_audio.get_ref() == null)
	gallery.queue_free()
	await frames(3)
