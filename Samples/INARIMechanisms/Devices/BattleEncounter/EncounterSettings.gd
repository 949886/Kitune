@tool
extends Resource
## Each member key belongs to one wave; bindings are supplied explicitly by
## the host. Source IDs stay in the audit JSON, never scene-tree lookups.
@export var on_field := true
@export_range(0, 30, 0.01, "or_greater") var phase_delay := 0.25
@export_range(0, 30, 0.01, "or_greater") var end_delay := 0.25
@export_range(0, 30, 0.01, "or_greater") var arrival_delay := 1.2
@export_range(0, 30, 0.01, "or_greater") var peaceful_delay := 0.25
@export var waves: Array[PackedStringArray] = []
@export var placements: Dictionary = {}
@export var arrival_kinds: Dictionary = {}
@export var arrival_offsets: Dictionary = {}
## Post-damage health ratio thresholds, keyed by the same explicit member key.
## Reaching one requests the next wave while surviving members stay active.
@export var thresholds: Dictionary = {}
