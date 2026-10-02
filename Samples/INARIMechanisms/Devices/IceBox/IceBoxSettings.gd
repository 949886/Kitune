@tool
extends Resource
## Source values live in the accompanying .tres. Distances use local pixels;
## rotating/scaling the scene transforms its grid and blocking queries together.
@export_range(1.0, 1024.0) var radius_pixels: float
@export_range(0.001, 10.0) var charge_seconds: float
@export_range(0.0, 30.0) var freeze_seconds: float
@export_range(0.001, 1.0) var blink_interval_max: float
@export_range(0.001, 1.0) var blink_interval_min: float
@export_range(0.001, 1.0) var outline_fade_seconds: float
