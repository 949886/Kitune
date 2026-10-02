extends Node
## Optional character-side component sharing the demo's exact buff clock.
## Hosts read extra_speed for horizontal movement, report attributed kills and
## connect feedback to their own character materials/trail/stamina effect.
signal changed(level: int)
signal stamina_feedback_requested(current_level: int, previous_level: int)
const Native = preload("../../Core/Native/Runtime/InariWindBuff.gd")
const Configuration = preload("WindBuffSettings.gd")
const Location = preload("../../PackageLocation.gd")
const Audio = preload("../../Core/DeviceAudio.gd")
@export var settings: Configuration = preload("WindBuffSettings.tres")
@export_range(0, 5, 0.01, "or_greater") var motion_time_scale := 1.0
var state := Native.new()
var audio: Node
var extra_speed: float:
	get:
		return state.extra_speed
var level: int:
	get:
		return state.level
var ratio: float:
	get:
		return state.ratio


func _ready() -> void:
	assert(
		settings.is_valid(),
		"Wind buff needs matching speed/duration profiles and positive active durations"
	)
	state.use_host_adapter = true
	state.speeds = settings.extra_speed_pixels.duplicate()
	state.durations = settings.durations.duplicate()
	state.feedback_requested.connect(stamina_feedback_requested.emit)
	# Sample before a default-priority host controller applies its movement.
	process_physics_priority = -10
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/WindStation/"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	audio = Audio.new()
	audio.folder = folder
	audio.groups = data.audio
	add_child(audio)


func _physics_process(delta: float) -> void:
	state.time_scale = motion_time_scale
	var previous: int = state.level
	state.advance(delta)
	if previous != state.level:
		changed.emit(state.level)


func request_from_station() -> void:
	state.request(maxi(1, state.level))
	changed.emit(state.level)


func notify_player_kill() -> void:
	# Caller must establish kill attribution. A kill with no active buff still
	# requests source feedback/audio, but never grants the first speed level.
	state.on_player_kill()
	audio.play_event("wind_buff_renewal", self)
	changed.emit(state.level)


func refresh_existing() -> bool:
	# RewardObserver renews the existing level; unlike a station it cannot
	# create the first level, and unlike a kill it cannot increase that level.
	if state.level <= 0:
		return false
	state.request(state.level)
	changed.emit(state.level)
	return true


func reset() -> void:
	state.reset()
	changed.emit(state.level)
