extends Resource
## Source duration and camera framing parameters. Duplicate to customize a pair.
@export_range(0, 3600, 1, "or_greater") var duration_seconds := 30.0
@export_range(0.01, 10, 0.01) var preview_damping := 2.0
@export_range(0.01, 200, 0.01, "or_greater") var preview_threshold := 32.0
@export var intro_seen := false
## Mirrors the destination's optional IsTimeOver / CollEnabled save record.
## A restored record initializes that terminal's digits to zero, even on success.
@export var destination_saved := false
@export var destination_time_over := false
@export var destination_enabled := true
