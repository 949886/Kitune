@tool
extends Resource
## Source profile selects geometry and materials. Defaults are exported from
## the corresponding original door, not inferred from the example layout.
@export_enum("WoodDoor", "HeavyDoor") var profile: String
@export var interaction_mask: int
@export_range(0.01, 100.0) var health: float
@export var invincible: bool
@export_range(0.01, 60.0) var fade_seconds: float
## Hosts may restore this before instancing, without replaying sound/debris.
@export var initial_broken := false
