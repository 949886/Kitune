extends Resource
## Source delays use different clocks: realtime before replacement, game time
## for its white/alpha fade. Positions are relative to the reusable scene root.
@export_range(0, 120, 0.01, "or_greater") var wait_seconds := 2.0
@export_range(0, 10, 0.01, "or_greater") var fade_seconds := 1.0
@export var kinds: Dictionary = {}
@export var placements: Dictionary = {}
