extends "WorkshopPlayer.gd"
## Host-only controller adapter. ScenePortal never knows these fields.
var controls_locked := false
var maintained_direction := Vector2.ZERO
var invincible := false
var dash_resets := 0


func begin_transition(data: Dictionary) -> void:
	var previous_input := Vector2(float(right) - float(left), 0)
	controls_locked = true
	left = false
	right = false
	pending_jump = false
	pending_attack = false
	maintained_direction = Vector2.ZERO
	if data.maintain_input:
		maintained_direction = previous_input if data.preserve_last_input else data.injected_input
	if data.grant_invincibility:
		invincible = true
	if data.reset_dash:
		dash_resets += 1


func scene_loaded() -> void:
	# Source OnAfterSceneChanged clears maintained input and invincibility
	# before fading back in; controls return after the fade completes.
	maintained_direction = Vector2.ZERO
	invincible = false
	left = false
	right = false
	velocity = Vector2.ZERO


func end_transition() -> void:
	scene_loaded()
	controls_locked = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not controls_locked:
		super._unhandled_key_input(event)


func _physics_process(delta: float) -> void:
	if controls_locked:
		left = maintained_direction.x < 0
		right = maintained_direction.x > 0
	super._physics_process(delta)
