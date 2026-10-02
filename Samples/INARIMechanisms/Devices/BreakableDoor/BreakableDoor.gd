@tool
extends "../../Core/DeviceHost.gd"
signal impacted(interaction: int)
signal broken
signal debris_cleared
signal attachments_invalidated
signal feedback_requested(kind: String)
const Native = preload("../../Core/Native/Runtime/OriginalDoor.gd")
const Configuration = preload("BreakableDoorSettings.gd")
@export var settings: Configuration = preload("WoodDoorSettings.tres")
@export_flags_2d_physics var solid_layers := 1
@export_flags_2d_physics var hit_layers := 2
@export_flags_2d_physics var debris_layers := 0
@export_flags_2d_physics var debris_collision_mask := 1
@export var random_seed := 17
var mechanism: Node


func _ready() -> void:
	var record := prepare(settings.profile)
	if Engine.is_editor_hint():
		return
	record.interactions = settings.interaction_mask
	record.health = settings.health
	record.invincible = settings.invincible
	record.fade_time = settings.fade_seconds
	mechanism = Native.new()
	mechanism.data = record
	mechanism.physics = document.physics.duplicate(true)
	mechanism.audio = audio
	mechanism.use_host_space = true
	mechanism.debris_layer = debris_layers
	mechanism.debris_mask = debris_collision_mask
	mechanism.launch_random = RandomNumberGenerator.new()
	mechanism.launch_random.seed = random_seed
	add_child(mechanism)
	var parts := {}
	for definition: Dictionary in record.pieces:
		var piece: Dictionary = definition.duplicate(true)
		piece.bodies = []
		piece.visuals = [visuals_by_go[piece.go]]
		mechanism.pieces.append(piece)
		parts[piece.go] = piece
	for collider: Dictionary in record.colliders:
		var body := StaticBody2D.new()
		body.transform = Native.Assets.matrix(collider.transform)
		body.collision_layer = solid_layers | hit_layers
		body.collision_mask = 0
		body.set_meta("device", self)
		body.set_meta("source_go", collider.go)
		body.set_meta("source_layer", collider.layer)
		for path: Array in collider.paths:
			var polygon := CollisionPolygon2D.new()
			var vertices := PackedVector2Array()
			for point: Array in path:
				vertices.append(Native.Assets.vec(point))
			polygon.polygon = vertices
			polygon.position = Native.Assets.vec(collider.offset)
			body.add_child(polygon)
		add_child(body)
		parts[collider.go].bodies.append(body)
	mechanism.impacted.connect(_on_impact)
	mechanism.debris_cleared.connect(func(): debris_cleared.emit())
	if settings.initial_broken:
		mechanism.broken = true
		mechanism.targetable = false
		for piece: Dictionary in mechanism.pieces:
			for body: StaticBody2D in piece.bodies:
				body.collision_layer = 0
			for visual: Node2D in piece.visuals:
				visual.hide()


func receive_hit(interaction: int, _actor: Node = null, direction := 1.0) -> bool:
	return mechanism.interact(interaction, 1.0 if direction >= 0.0 else -1.0)


func receive_enemy_damage(amount: float, direction := 1.0) -> void:
	mechanism.receive_enemy_damage(amount, 1.0 if direction >= 0.0 else -1.0)


func is_broken() -> bool:
	return is_instance_valid(mechanism) and mechanism.broken


func can_attach_projectile() -> bool:
	return not is_broken() and document.record.can_shuriken_hit


func _on_impact(interaction: int, destroyed: bool) -> void:
	impacted.emit(interaction)
	if destroyed:
		if interaction != 64:
			attachments_invalidated.emit()
		feedback_requested.emit("StrongAttack" if interaction == 8 else "InteractiveWall")
		broken.emit()
	else:
		feedback_requested.emit("Attack")
