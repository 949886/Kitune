@tool
extends Resource
## Defaults are exported from the original closed exit door in level5.
## Hosts can restore a saved state by assigning initial_open before instancing.
@export var initial_open: bool
@export_range(0.0, 1.0) var collider_release_fraction: float
