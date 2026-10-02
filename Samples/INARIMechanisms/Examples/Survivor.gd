extends "WorkshopPlayer.gd"
## Example-only health/respawn policy. Devices invoke these explicit callbacks.
signal hurt
@export var controlled := true
@export var maximum_health := 100.0
@export var source_origin_offset := Vector2(0, -32)
var health := 37.0
var dead := false
var invulnerable_seconds := 0.0
var checkpoint: Dictionary = {}
var damage_count := 0
var respawn_physics_frame := -10


func _unhandled_key_input(event: InputEvent) -> void:
	if controlled:
		super._unhandled_key_input(event)


func _physics_process(delta: float) -> void:
	invulnerable_seconds = maxf(0, invulnerable_seconds - delta)
	modulate = Color("f4bb62") if not controlled else Color.WHITE
	if dead:
		modulate = Color("53616a")
		return
	if invulnerable_seconds > 0:
		modulate = Color("97b8ff")
	super._physics_process(delta)


func can_save() -> bool:
	return not dead


func can_take_damage() -> bool:
	# Godot's overlap list still describes the previous physics step immediately
	# after a teleport. Let it refresh before enabling damage at the new spawn.
	return (
		not dead
		and invulnerable_seconds <= 0
		and Engine.get_physics_frames() > respawn_physics_frame + 2
	)


func take_damage(amount: float) -> bool:
	if not can_take_damage():
		return false
	damage_count += 1
	health = maxf(0, health - amount)
	dead = health == 0
	hurt.emit()
	return true


func save_checkpoint(payload: Dictionary) -> void:
	checkpoint = payload.duplicate(true)
	# This controller's origin is at its feet; the source marker identifies a
	# point above them. The conversion belongs to the host, not the save device.
	checkpoint.position -= global_transform.basis_xform(source_origin_offset)


func respawn(fallback: Vector2) -> void:
	respawn_physics_frame = Engine.get_physics_frames()
	global_position = checkpoint.get("position", fallback)
	facing = float(checkpoint.get("facing", 1))
	velocity = Vector2.ZERO
	health = maximum_health
	dead = false
	invulnerable_seconds = 0
	left = false
	right = false
	pending_jump = false
	pending_attack = false
