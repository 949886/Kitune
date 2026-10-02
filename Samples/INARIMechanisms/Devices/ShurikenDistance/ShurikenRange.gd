extends Node
## One shared value per player, as in PlayerStateMachine. No overlap stack:
## any eligible region exit writes zero, even inside a different region.
signal distance_changed(units: float)
@export var settings: Resource = preload("DefaultRange.tres")
var additive_distance := 0.0


func set_additive_distance(value: float) -> void:
	additive_distance = value
	distance_changed.emit(value)


## Source captures only the region bonus. Its combat profile's base distance
## is still read live, so a host changing the profile also affects old throws.
func capture_bonus() -> float:
	return additive_distance


func limit_for(captured_bonus: float) -> float:
	return (settings.base_distance + captured_bonus) * settings.pixels_per_unit


func current_limit() -> float:
	return limit_for(additive_distance)


func exceeds_limit(projectile: Vector2, player: Vector2, captured_limit: float) -> bool:
	return projectile.distance_to(player) > captured_limit
