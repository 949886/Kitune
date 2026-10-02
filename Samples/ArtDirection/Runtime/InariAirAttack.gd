extends RefCounted
## JumpAttack keeps its entry GFX pose while collision facing follows movement.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var actor: CharacterBody2D
var settings: Dictionary
var active := false
var entry_facing := 1.0
var visual_facing := 1.0
var finish_frame := -1


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "air_attack.json")


func enter() -> void:
	active = true
	finish_frame = -1
	entry_facing = actor.facing
	_reset_climb()
	visual_facing = (
		entry_facing
		if actor.targeting.using_gamepad
		else _mouse_side(actor.body_shape.global_position.x)
	)
	actor.facing = visual_facing
	actor.sprite.facing = visual_facing
	actor.can_air_attack = false
	actor.path_time = actor.path_duration
	actor.path_collision_type = "Airing"
	actor.velocity.y = -float(actor.attack_info.AttackMovementInfo.Distance) * actor.units
	actor.audio.play(settings.entry_sound)


func can_finish() -> bool:
	if actor.is_on_floor() or actor.throw_buffer_until > actor.clock:
		return true
	if finish_frame < 0:
		finish_frame = Engine.get_physics_frames()
	return Engine.get_physics_frames() >= finish_frame + int(settings.airborne_exit_wait_updates)


func leave() -> void:
	if not active:
		return
	active = false  # State changes and explicit handoffs may both reach this hook.
	var input: Vector2 = actor.movement_input.read_direction()
	if input in [Vector2.LEFT, Vector2.RIGHT] and _mouse_side(actor.global_position.x) != input.x:
		actor.facing = -entry_facing
	if actor.facing == entry_facing:
		_reset_climb()
		actor.move_source_offset(
			Vector2.LEFT * entry_facing * float(settings.exit_distance) * actor.units
		)
		actor.facing = entry_facing
	actor.sprite.facing = actor.facing
	actor.sprite._refresh_frame()


func _reset_climb() -> void:
	actor.climbing = false
	actor.ceiling_hang = false
	actor.drop_time = 0.0
	actor.collision_mask |= Collision.ONE_WAY


func _mouse_side(origin_x: float) -> float:
	# Unity Mathf.Sign(0) is +1. Exit queries the component origin; Enter uses
	# the collider center, as the two native input helpers do.
	return 1.0 if actor.get_global_mouse_position().x >= origin_x else -1.0
