extends Node
## Original BGMManager event policy. Each host owns one mixer and shares it
## between rooms; the native bridge owns event/DLL lifetimes, not game state.
signal parameters_applied(family: String, values: Dictionary)
signal bgm_changed(guid: String)
signal audio_failed(command: String, result: int)
const Location = preload("../../PackageLocation.gd")
@export_enum("realtime", "silent") var output_mode := "realtime"
## Absolute WAV path selects deterministic offline output for validation.
@export var capture_path := ""
@export_range(0, 1) var volume := 1.0
var native: RefCounted
var document: Dictionary
var handles: Dictionary = {}
var current_bgm := ""
var bgm_starts := 0
var failures: Array[Dictionary] = []
var initialized := false
var _offline := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var folder: String = (Location as Script).resource_path.get_base_dir()
	document = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/EnvironmentAudio/device.json"))
	if not ClassDB.class_exists("InariFmodRuntime"):
		GDExtensionManager.load_extension(folder + "/Core/Fmod/inari_fmod.gdextension")
	if not ClassDB.class_exists("InariFmodRuntime"):
		_fail("extension", 10011)
		return
	native = ClassDB.instantiate("InariFmodRuntime")
	var mode := capture_path if not capture_path.is_empty() else output_mode
	# A host test can suppress device output without changing scene resources.
	if capture_path.is_empty() and not OS.get_environment("INARI_AUDIO_OUTPUT").is_empty(): mode = OS.get_environment("INARI_AUDIO_OUTPUT")
	_offline = mode != "realtime"
	_command("open", ProjectSettings.globalize_path(folder + "/Core/Fmod/bin"),
		ProjectSettings.globalize_path(folder + "/Assets/EnvironmentAudio/Banks"), mode)
	if not failures.is_empty():
		close()
		return
	initialized = true
	for pair: Array in [["reverb", "Reverb"], ["ambient", "Ambient"], ["death", "DieSnapShot"]]:
		handles[pair[0]] = int(_command("create", document.profile.events[pair[1]]))
		_command("start", str(handles[pair[0]]))
	set_volume(volume)


func _command(command: String, first := "", second := "", third := "") -> String:
	if native == null: return ""
	var result: String = native.call("invoke", command, first, second, third)
	var code := int(result.get_slice(":", 0))
	if code != 0:
		_fail(command, code)
		return ""
	return result.substr(result.find(":") + 1)


func _fail(command: String, code: int) -> void:
	failures.append({"command": command, "result": code})
	audio_failed.emit(command, code)
	push_error("INARI FMOD %s failed: %d" % [command, code])


func _process(_delta: float) -> void:
	if initialized: _command("update")


func set_volume(value: float) -> void:
	volume = value
	if not initialized: return
	for bus: String in ["bus:/BGM", "bus:/AMB"]: _command("volume", bus, str(value))


## Null BGM parameters means set every event parameter to one. An empty
## dictionary means change nothing. Same GUID updates without restarting music.
func change_bgm(guid: String, values = {}) -> void:
	if not initialized or guid.is_empty() or guid == "00000000-0000-0000-0000-000000000000": return
	if guid == current_bgm:
		_apply("bgm", _bgm_values(guid, values))
		return
	stop_bgm()
	handles.bgm = int(_command("create", guid))
	if int(handles.bgm) == 0: return
	current_bgm = guid
	_apply("bgm", _bgm_values(guid, values))
	_command("start", str(handles.bgm))
	bgm_starts += 1
	bgm_changed.emit(guid)


func _bgm_values(guid: String, values) -> Dictionary:
	if values != null: return values
	var defaults := {}
	for key: String in document.events[guid].parameters: defaults[key] = 1.0
	return defaults


func _apply(family: String, values: Dictionary) -> void:
	if not initialized or not handles.has(family): return
	for key: String in values:
		_command("set", str(handles[family]), key, str(float(values[key])))
	parameters_applied.emit(family, values.duplicate(true))


func apply_zone(family: String, guid: String, values: Dictionary) -> void:
	if family == "bgm": change_bgm(guid, values)
	else: _apply(family, values)


func parameter(family: String, key: String) -> Vector2:
	assert(handles.has(family))
	var values := _command("get", str(handles[family]), key).split(",")
	if values.size() != 2: return Vector2(NAN, NAN)
	return Vector2(float(values[0]), float(values[1])) # requested, final (seek-speed aware)


func stop_bgm() -> void:
	if handles.has("bgm"):
		_command("stop_release", str(handles.bgm))
		handles.erase("bgm")
	current_bgm = ""


func reset_ambience_and_reverb() -> void:
	for pair: Array in [["ambient", "Ambient"], ["reverb", "Reverb"]]:
		var values := {}
		for key: String in document.events[document.profile.events[pair[1]]].parameters: values[key] = 0.0
		_apply(pair[0], values)


func enter_menu() -> void:
	reset_ambience_and_reverb()
	change_bgm(document.profile.events.MainMenu, null)


## Offline mode advances the actual NRT DSP clock; ordinary runtime update
## leaves timing to FMOD's audio thread, independent of Engine.time_scale.
func render_frames(frames: int) -> void:
	assert(initialized and _offline and frames >= 0)
	var errors_before := failures.size()
	var end := int(_command("clock")) + frames
	while failures.size() == errors_before and int(_command("clock")) < end:
		_command("update")


func close() -> void:
	initialized = false
	if native != null: _command("close")
	native = null
	handles.clear()
	current_bgm = ""


func _exit_tree() -> void:
	close()
