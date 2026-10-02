@tool
extends Resource
## Exported source placement/timing. One-way single use matches this cabin's
## shipped button; return trips require a separate host-authored mechanism.
@export var travel_offset := Vector2.ZERO
@export_range(0.01, 1000, 0.01, "or_greater") var speed_pixels_per_second := 1.0
@export_range(0, 30, 0.01, "or_greater") var wait_seconds := 0.0
@export_range(0, 5, 0.01, "or_greater") var ease_amount := 0.0
@export_range(0, 10, 0.01, "or_greater") var door_release_seconds := 0.0
@export_range(0, 10, 0.01, "or_greater") var outline_fade_seconds := 0.0
@export var destination_key := ""
@export var scene_exit_offset := Vector2.ZERO
@export var scene_exit_size := Vector2.ONE
