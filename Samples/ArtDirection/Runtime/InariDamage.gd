extends RefCounted
## Source runtime HP and hit recovery, separate from movement and animation state.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var actor: CharacterBody2D
var settings: Dictionary
var health := 0
var maximum := 0
var blink_elapsed := 0.0
var blinking := false


func configure(player: CharacterBody2D) -> void:
	actor = player
	settings = Assets.read_json(Assets.ROOT + "player_damage.json")
	reset()


func reset() -> void:
	maximum = int(settings.story_hp if actor.story_mode else settings.normal_hp)
	health = maximum
	blinking = false
	blink_elapsed = 0.0
	actor.sprite.modulate.a = 1.0
	actor.health_changed.emit(health, maximum)


func accepts_damage() -> bool:
	return not actor.dead and not blinking and not settings.immune_states.has(actor.action_state)


func receive(amount: float, knockback: Dictionary = {}) -> bool:
	if amount < 0.0 or not accepts_damage():
		return false
	actor.air_attack.leave()

	# PlayerStateMachine changes its runtime HP only for damage without a
	# KnockbackInfo. Physical knockback is a separate, non-HP reaction there.
	if knockback.is_empty():
		health = clampi(health - int(amount), 0, maximum)
		actor.health_changed.emit(health, maximum)
		actor.camera_shake_requested.emit("Damaged")
		actor.audio.play("hit")
		if health == 0:
			actor.die(true)
			return true
	else:
		var distance: float = float(knockback.Power) * float(knockback.DirectionX) * actor.units
		actor._start_motion(distance / actor.facing, knockback.Duration, knockback.Curve, "Hit")

	blinking = true
	blink_elapsed = 0.0
	actor.sprite.modulate.a = float(settings.blink_alpha)
	# The original Hit coroutine immediately returns to Idle. Clear the old
	# attack instead of inventing a hurt clip or a two-second input lock.
	actor.action_state = ""
	actor.attack_info.clear()
	actor.attack_buffer_until = 0.0
	actor.throw_buffer_until = 0.0
	actor.camera_shake_requested.emit("Damaged")
	actor.sprite.play("idle", true)
	return true


func advance(delta: float) -> void:
	if not blinking:
		return
	blink_elapsed += delta
	if blink_elapsed + 0.000001 >= float(settings.blink_duration):
		blinking = false
		actor.sprite.modulate.a = 1.0
		return
	var step := floori((blink_elapsed + 0.000001) / float(settings.blink_interval))
	actor.sprite.modulate.a = float(settings.blink_alpha) if step % 2 == 0 else 1.0


func mark_dead() -> void:
	var changed := health != 0
	health = 0
	blinking = false
	actor.sprite.modulate.a = 1.0
	if changed:
		actor.health_changed.emit(health, maximum)
