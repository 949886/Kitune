extends Node
## PlayerStateMachine.ChromaticAberration uses a MonoBehaviour coroutine, so
## the game's selective hit-stop does not pause its two-poll wait or timer.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")

var settings: Dictionary = Assets.read_json(Assets.ROOT + "chromatic.json")
var presentation: ShaderMaterial
var intensity := 0.0
var jobs: Array[Dictionary] = []


func bind_material(value: ShaderMaterial) -> void:
	presentation = value
	_apply(intensity)


func trigger(stack_index: int, delta: float) -> void:
	var index := clampi(stack_index, 0, settings.duration.size() - 1)
	var job := {
		"elapsed": 0.0,
		"duration": float(settings.duration[index]),
		"intensity": float(settings.intensity[index]),
		"polls": 0,
		"created_frame": Engine.get_process_frames()
	}
	jobs.append(job)
	_resume(job, delta)


func _process(delta: float) -> void:
	advance(delta, true)


func advance(delta: float, respect_creation_frame := false) -> void:
	for job: Dictionary in jobs:
		if respect_creation_frame and job.created_frame == Engine.get_process_frames():
			continue
		job.polls += 1
		if job.polls >= int(settings.wait_polls):
			_resume(job, delta)
	jobs = jobs.filter(func(job: Dictionary): return not job.get("finished", false))


func _resume(job: Dictionary, delta: float) -> void:
	if job.elapsed < job.duration:
		_apply(job.intensity)
		# The source accumulates C# float delta once per resumed iteration,
		# not wall time spent waiting. Preserve its boundary rounding as well.
		job.elapsed = PackedFloat32Array([job.elapsed + PackedFloat32Array([delta])[0]])[0]
		job.polls = 0
	else:
		_apply(0.0)
		job.finished = true


func _apply(value: float) -> void:
	# VolumeParameter.Override and FloatParameter.Interp write m_Value directly:
	# their 1.5/1.75 inputs bypass ClampedFloatParameter's property setter.
	intensity = value
	if is_instance_valid(presentation):
		var amount := value * float(settings.shader_amount_scale)
		presentation.set_shader_parameter("chromatic_amount", amount if settings.active else 0.0)
