extends RefCounted
## Cinemachine legacy impulse: source cosine channels, envelope and propagation.
## CameraShakeManager clears the previous event whenever it starts another one.

const SourceCurve = preload("UnityCurve.gd")
const EPSILON := 0.0001

var data: Dictionary
var active: Dictionary = {}
var envelope: Dictionary = {}
var elapsed := 0.0
var phase := 0.0
var force := 1.0
var origin := Vector2.ZERO
var event_name := ""
var event_serial := 0


func configure(source: Dictionary) -> void:
	data = source
	force = float(data.strengths[data.default_setting])


func generate(kind: String, position: Vector2, start_phase := NAN) -> void:
	clear()
	if not data.entries.has(kind):
		return
	active = data.entries[kind]
	event_name = kind
	event_serial += 1
	origin = position
	var definition: Dictionary = active.definition
	envelope = definition.m_TimeEnvelope.duplicate(true)
	if envelope.m_ScaleWithImpact:
		envelope.m_DecayTime *= sqrt(_velocity().length())
	if definition.m_Randomize:
		phase = randf_range(-1000.0, 1000.0) if is_nan(start_phase) else start_phase


func advance(delta: float, listener: Vector2) -> Vector2:
	elapsed += delta
	if not active.is_empty() and not envelope.m_HoldForever:
		var duration: float = envelope.m_AttackTime + envelope.m_SustainTime + envelope.m_DecayTime
		var definition: Dictionary = active.definition
		var travel: float = (
			(definition.m_ImpactRadius + definition.m_DissipationDistance)
			/ maxf(1.0, definition.m_PropagationSpeed)
		)
		if elapsed >= duration + travel:
			clear()
	return sample(elapsed, listener)


func sample(time: float, listener: Vector2) -> Vector2:
	if active.is_empty():
		return Vector2.ZERO
	var definition: Dictionary = active.definition
	if (int(definition.m_ImpulseChannel) & int(data.listener.m_ChannelMask)) == 0:
		return Vector2.ZERO
	var displacement := listener - origin
	var distance := displacement.length()
	var local_time := time - distance / maxf(1.0, definition.m_PropagationSpeed)
	var gain := envelope_gain(local_time) * distance_gain(distance)
	if is_zero_approx(gain):
		return Vector2.ZERO

	var wave := Vector2.ZERO
	var wave_time := phase + local_time * float(definition.m_FrequencyGain)
	for octave: Dictionary in active.position_noise:
		wave.x += _channel(octave.X, wave_time)
		wave.y += _channel(octave.Y, wave_time)
	var velocity := _velocity()
	wave *= velocity.length() * float(definition.m_AmplitudeGain) * gain
	# All geometry in this class is Unity world units, with Y pointing up.
	if velocity.length() > EPSILON:
		wave = wave.rotated(velocity.angle() + PI / 2.0)
	if int(definition.m_DirectionMode) == 1 and distance > EPSILON:
		var angle := wrapf(displacement.angle() - PI / 2.0, -PI, PI)
		var radius: float = definition.m_ImpactRadius
		if radius > EPSILON:
			angle *= 1.0 - cos(PI * clampf(distance / radius, 0.0, 1.0) / 2.0)
		wave = wave.rotated(angle)
	return wave * float(data.listener.m_Gain)


func envelope_gain(time: float) -> float:
	if time < 0.0:
		return 0.0
	var attack: float = envelope.m_AttackTime
	if time < attack and attack > EPSILON:
		if envelope.m_AttackShape.m_Curve.size() >= 2:
			return SourceCurve.evaluate(envelope.m_AttackShape, time / attack)
		return 0.0 if time < EPSILON else 1.0 - pow(0.01, time / attack)
	time -= attack
	if envelope.m_HoldForever or time < float(envelope.m_SustainTime):
		return 1.0
	time -= float(envelope.m_SustainTime)
	var decay: float = envelope.m_DecayTime
	if time < decay and decay > EPSILON:
		if envelope.m_DecayShape.m_Curve.size() >= 2:
			return SourceCurve.evaluate(envelope.m_DecayShape, time / decay)
		return 1.0 if time < EPSILON else pow(0.01, time / decay)
	return 0.0


func distance_gain(distance: float) -> float:
	var definition: Dictionary = active.definition
	distance = maxf(0.0, distance - maxf(0.0, definition.m_ImpactRadius))
	var limit: float = definition.m_DissipationDistance
	if distance >= limit:
		return 0.0
	match int(definition.m_DissipationMode):
		1:
			return 0.5 * (1.0 + cos(PI * distance / limit))
		2:
			return pow(0.01, distance / limit)
		_:
			return 1.0 - distance / limit


func clear() -> void:
	active = {}
	envelope = {}
	elapsed = 0.0
	phase = 0.0
	event_name = ""


func _velocity() -> Vector2:
	return Vector2(active.velocity.x, active.velocity.y) * force


func _channel(channel: Dictionary, time: float) -> float:
	if is_zero_approx(channel.Amplitude):
		return 0.0
	return cos(float(channel.Frequency) * time * TAU) * float(channel.Amplitude) * 0.5
