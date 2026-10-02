extends RefCounted
## CheckAiringInGamePad changes registered objects, not the global engine clock.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var actor: CharacterBody2D
var settings: Dictionary


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "aim_time.json")
	assert(settings.excluded_state == "MultiThrow")


func update() -> void:
	if not is_instance_valid(actor.weak_dash.stage) or not actor.targeting.using_gamepad:
		return
	if actor.dead or actor.source_time_scale == 0.0 or actor.action_state == "multi_throw":
		return
	var pressed: bool = actor.targeting.right_stick_pressed()
	var air: bool = collision_type() in settings.air_collision_types
	var slow: bool = pressed and air and not actor.climbing and not actor.ceiling_hang
	actor.weak_dash.stage.combat_clock.set_scale(
		settings.air_scale if slow else settings.normal_scale
	)


func collision_type() -> String:
	# Translate the study controller's current movement mode to the source flag
	# table. Airborne dash and heavy-hit movement do not carry the native Air flag.
	if actor.path_time < actor.path_duration:
		return actor.path_collision_type
	match actor.action_state:
		"weakpoint_execution":
			return "DashAttack"
		"dash", "teleport":
			return "Dash"
		"attack", "heavy_attack":
			return "Attack"
		"hit":
			return "Hit"
		"attack_air":
			return "Airing"
	if actor.is_on_floor():
		return "Idle"
	if actor.wall_jump_time > 0.0:
		return "ClimbJump"
	if actor.action_state == "throw":
		return "Airing"
	return "Jump" if actor.velocity.y < 0.0 else "Falling"


func reset() -> void:
	if is_instance_valid(actor.weak_dash.stage):
		actor.weak_dash.stage.combat_clock.reset()
