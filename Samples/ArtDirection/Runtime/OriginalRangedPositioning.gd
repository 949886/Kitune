extends RefCounted
## RangedPositioningRule runs for the whole group on ranged AttackReady entry.


static func execute(stage: Node, settings: Dictionary) -> void:
	var active: Array[Node] = []
	for enemy: Node in stage.enemies:
		if is_instance_valid(enemy) and enemy.source_active():
			active.append(enemy)
	for enemy: Node in active:
		var combat: RefCounted = enemy.ranged_combat
		# Throw attacks remain pending; all active enemies still count as neighbours.
		if combat.settings.is_empty() or combat.state != "ready" or not combat.retargetable:
			continue
		var count := nearby_count(stage.navigation, enemy, active, float(settings.path_nodes))
		if count > int(settings.count_threshold):
			combat.retargetable = false
			combat.request_retarget()


static func nearby_count(
	navigation: RefCounted, owner: Node, active: Array[Node], maximum: float
) -> int:
	var start: Vector2i = navigation.world_cell(owner.position + owner.body_shape.position)
	var count := 0
	for enemy: Node in active:
		var end: Vector2i = navigation.world_cell(enemy.position + enemy.body_shape.position)
		var path: Array[Vector2i] = navigation.path(start, end, true)
		if not path.is_empty() and path.size() <= maximum:
			count += 1
	return count
