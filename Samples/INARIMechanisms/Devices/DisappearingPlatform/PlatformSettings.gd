@tool
extends Resource
## Source presets contain geometry, sprites and animation timing for one connected
## tile group. Negative timing overrides preserve the values shipped in INARI.
@export var source_key := "level7_18316_0"
@export_range(-1.0, 30.0, 0.01) var disappear_delay := -1.0
@export_range(-1.0, 30.0, 0.01) var hidden_seconds := -1.0
@export_range(0.0, 4.0, 0.01) var time_scale := 1.0
@export var sound_enabled := true
