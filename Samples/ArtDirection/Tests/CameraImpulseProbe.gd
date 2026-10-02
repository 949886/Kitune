extends SceneTree
## Quantitative source-wave checks; camera and combat integration are separate.

const Impulse = preload("res://Samples/ArtDirection/Runtime/InariCameraImpulse.gd")
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")


func _initialize() -> void:
	var camera: Dictionary = Assets.read_json(Assets.ROOT + "camera.json")
	var signal_source := Impulse.new()
	signal_source.configure(camera.impulses)
	assert(camera.impulses.entries.size() == 12)
	signal_source.generate("Attack", Vector2.ZERO, 0.0)
	# Source: cosine at 8 Hz, per-axis peak .3 / 2 * 5 = .75 Unity units.
	assert(signal_source.sample(0.0, Vector2.ZERO).distance_to(Vector2(0.75, 0.75)) < 0.000001)
	assert(signal_source.sample(0.03125, Vector2.ZERO).length() < 0.000001)
	assert(
		signal_source.sample(0.025, Vector2.ZERO).distance_to(Vector2.ONE * 0.231762746) < 0.000001
	)
	# .05 s sustain, then a .2 s decay: halfway through decay leaves 10%.
	assert(absf(signal_source.envelope_gain(0.15) - 0.1) < 0.000001)
	assert(signal_source.sample(0.251, Vector2.ZERO) == Vector2.ZERO)
	assert(signal_source.sample(-0.01, Vector2.ZERO) == Vector2.ZERO)

	# At 500 units the wave arrives after .005 s, with half its initial gain.
	# RotateTowardSource rotates the upward reference axis towards the listener.
	assert(signal_source.sample(0.004, Vector2(500, 0)) == Vector2.ZERO)
	assert(
		signal_source.sample(0.005, Vector2(500, 0)).distance_to(Vector2(0.375, -0.375)) < 0.00001
	)
	assert(signal_source.sample(0.02, Vector2(1000, 0)) == Vector2.ZERO)

	signal_source.force = camera.impulses.strengths.Half
	signal_source.generate("Attack", Vector2.ZERO, 0.0)
	assert(signal_source.sample(0.0, Vector2.ZERO).distance_to(Vector2.ONE * 0.375) < 0.000001)
	assert(absf(float(signal_source.envelope.m_DecayTime) - 0.141421356) < 0.000001)
	signal_source.force = camera.impulses.strengths.Off
	signal_source.generate("StrongAttack", Vector2.ZERO, 0.0)
	assert(signal_source.sample(0.025, Vector2.ZERO) == Vector2.ZERO)

	signal_source.force = camera.impulses.strengths.Full
	signal_source.generate("StrongAttack", Vector2.ZERO, 0.0)
	assert(signal_source.sample(0.0, Vector2.ZERO).distance_to(Vector2.ONE * 1.5) < 0.000001)
	signal_source.generate("ShurikenDash", Vector2.ZERO, 0.0)
	assert(signal_source.sample(0.0, Vector2.ZERO).distance_to(Vector2.ONE * 0.0975) < 0.000001)
	assert(signal_source.event_name == "ShurikenDash", "New source events replace rather than add")
	signal_source.advance(1.0, Vector2.ZERO)
	assert(signal_source.active.is_empty(), "Expired wave must be removed")
	for iteration in 20:
		signal_source.generate("Attack", Vector2.ZERO)
		assert(signal_source.phase >= -1000.0 and signal_source.phase <= 1000.0)
	print("CAMERA_IMPULSE_PASS")
	quit()
