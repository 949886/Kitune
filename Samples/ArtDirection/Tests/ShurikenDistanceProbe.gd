extends SceneTree
## Real native actor/projectile against a physics wall. Imported source regions
## are placed at their exact coordinates in an isolated fixture physics area;
## this does not claim the complete level12/28 artwork is imported.
const Adapter = preload("res://Samples/ArtDirection/Runtime/InariShurikenDistanceZones.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
class RegionFixture extends Node2D:
	var data := {"source": "level12"}
var lab: Node


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func fly(player: Node, count: int) -> void:
	for i in count:
		player._update_projectile(1.0 / 60.0)
		await frames(1)


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	await frames(5)
	var player: Node = lab.player
	player.set_physics_process(false)
	for source: String in ["level12", "level28"]:
		var fixture := RegionFixture.new()
		fixture.data.source = source
		lab.viewport.add_child(fixture)
		var adapter := Adapter.new()
		fixture.add_child(adapter)
		adapter.configure(fixture, player, func(): return false)
		assert(adapter.zones.size() == 1)
		var zone: Area2D = adapter.zones[0]
		assert(zone.transform == zone.settings.source_transform and zone.actor_layers == player.collision_layer)
		var center: Vector2 = zone.to_global(zone.settings.trigger_offset)
		var width: float = zone.settings.trigger_size.x
		var inside := center - Vector2(width / 2 - 20, 0)
		var outside := inside - Vector2(100, 0)
		player.global_position = outside
		await frames(4)
		assert(player.shuriken_range.additive_distance == 0)
		var baseline: float = float(player.combat.ShurikenMaxDistance) * player.units
		var bonus: float = zone.settings.additive_distance * player.units
		var wall := StaticBody2D.new()
		wall.collision_layer = Collision.PROJECTILE_SURFACE
		wall.position = inside + player.body_shape.position + Vector2(baseline + bonus / 2, 0)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(10, 80)
		shape.shape = box
		wall.add_child(shape)
		fixture.add_child(wall)
		await frames(2)
		player.throw_projectile(Vector2.RIGHT)
		assert(player.projectile_range_pixels == baseline)
		await fly(player, 40)
		assert(not player.projectile_active and not player.projectile_stuck)
		player.global_position = inside
		await frames(4)
		assert(player.shuriken_range.additive_distance == zone.settings.additive_distance)
		player.throw_projectile(Vector2.RIGHT)
		var captured: float = player.projectile_range_pixels
		assert(captured == baseline + bonus)
		player.global_position = outside
		await frames(4)
		assert(player.shuriken_range.additive_distance == 0)
		await fly(player, 40)
		assert(player.projectile_active and player.projectile_stuck)
		assert(player.projectile_surface.get_ref() == wall and player.projectile_range_pixels == captured)
		var original_base: float = player.combat.ShurikenMaxDistance
		player.combat.ShurikenMaxDistance += 1.0
		assert(player.projectile_range_pixels == captured + player.units)
		player.combat.ShurikenMaxDistance = original_base
		# Strict distance is from the moving actor, not total path travelled.
		player.global_position = player.projectile.global_position - player.body_shape.position - Vector2(captured, 0)
		player._update_projectile(0)
		assert(player.projectile_active)
		player.global_position.x -= 1
		player._update_projectile(0)
		assert(not player.projectile_active)
		fixture.queue_free()
		await frames(3)
	var state: WeakRef = weakref(player.shuriken_range)
	lab.load_level(0)
	await frames(4)
	assert(state.get_ref() == null and lab.player.shuriken_range.additive_distance == 0)
	lab.queue_free()
	await frames(3)
	print("NATIVE_SHURIKEN_DISTANCE_PASS")
	quit()
