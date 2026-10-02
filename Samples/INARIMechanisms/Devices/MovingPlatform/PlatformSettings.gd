@tool
extends Resource
## Pixel-space route relative to the scene root. Default values are supplied by
## the source-generated .tres, so tuning is editable without changing scripts.
@export var travel_offset := Vector2.ZERO
@export_range(0.01, 10000.0, 0.01) var speed_pixels_per_second: float
@export_range(0.0, 60.0, 0.01) var wait_seconds: float
@export_range(0.0, 10.0, 0.01) var ease_amount: float
@export var cyclic: bool
@export var stop_at_waypoints: bool
