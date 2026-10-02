extends Node2D
## Self-disposing source particle burst, owned by the portable device.
const Emitter = preload("Native/Runtime/OriginalParticleEmitter.gd")
var sorting: Callable = func(order: Array): return int(order[1])
var emitters: Array[Node] = []


func configure(
	definition: Dictionary, gravity: Dictionary, folder: String, seed_value: int
) -> void:
	for record: Dictionary in definition.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure_source(
			record.duplicate(true), self, gravity, seed_value + emitters.size(), folder
		)
		emitters.append(emitter)


func _process(_delta: float) -> void:
	if (
		not emitters.is_empty()
		and emitters.all(func(emitter: Node): return not emitter.is_processing())
	):
		queue_free()
