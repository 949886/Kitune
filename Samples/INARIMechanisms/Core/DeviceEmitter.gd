extends "Native/Runtime/OriginalParticleEmitter.gd"
var animation_active := true


## Animator GameObject-active tracks hide and stop authored child systems.
## Re-enabling a GameObject restarts its play-on-awake system. Repeated active
## samples from the same animation must not restart a completed one-shot.
func set_animation_visibility(active: bool) -> void:
	if active and not animation_active and system.playOnAwake:
		clock = 0.0
		delay = Values.number(system.startDelay, 0, random.randf())
		next_rate = 0.0
		emission_cycle = -1
		distance_remainder = 0.0
		bursts.clear()
		previous_origin = _world_pose().origin
	if active == animation_active:
		return
	animation_active = active
	visible = active
	set_process(active)
	if not active:
		for particle: Dictionary in particles:
			particle.visual.queue_free()
		particles.clear()
		queue_redraw()
