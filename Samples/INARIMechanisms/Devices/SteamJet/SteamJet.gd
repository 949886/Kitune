@tool
extends Node2D
## Tutorial SteamTrap, with original geometry, particles and idle animation.
## There is no authored damage collider. Attach a separate DamageZone if desired.
signal emission_changed(active: bool)
const Emitter = preload("../../Core/Native/Runtime/OriginalParticleEmitter.gd")
const Animator = preload("../../Core/Native/Runtime/OriginalSceneAnimation.gd")
const DeviceSprite = preload("../../Core/DeviceSprite.gd")
const Location = preload("../../PackageLocation.gd")

## Folder under this package's Assets. The ceiling preset selects its own
## exported source record; it does not modify the temple preset's particles.
@export var source_asset := "SteamJet"
@export var emitting := true:
	set(value):
		emitting = value
		for emitter: Node in emitters:
			emitter.system.EmissionModule.enabled = value
		if is_inside_tree():
			emission_changed.emit(value)
@export_range(0.0, 4.0, 0.05) var simulation_speed := 1.0:
	set(value):
		simulation_speed = value
		for emitter: Node in emitters:
			emitter.time_scale_override = float(emitter.system.simulationSpeed) * value
@export var random_seed := 17
@export var preview_in_editor := true
var emitters: Array[Node] = []
## Unity sorts by layer before order: fire on layer 6/order -500 is in front
## of the layer 0 nozzle, not behind the host's background. Compact ranks keep
## the internal SortingGroup order without leaking Unity's large order values.
var sorting: Callable = _particle_sort_order
var _sort_keys: Array[Vector2i] = []
var _last_canvas_z := 0
var source: Dictionary


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/" + source_asset + "/"
	source = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	for record: Dictionary in source.sprites:
		_register_sort_key(record.sort)
	for record: Dictionary in source.emitters:
		_register_sort_key([record.renderer.m_SortingLayer, record.renderer.m_SortingOrder])
	_sort_keys.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var visuals := {}
	for record: Dictionary in source.sprites:
		var visual := DeviceSprite.new()
		add_child(visual)
		visual.configure(record, source.sprite_info[record.sprite], folder)
		visual.z_index = _local_sort_order(record.sort)
		visuals[record.go] = visual
	if Engine.is_editor_hint():
		return
	var animation := Animator.new()
	add_child(animation)
	animation.configure(source.tracks, visuals)
	for record: Dictionary in source.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure_source(
			record.duplicate(true), self, source.gravity, random_seed + emitters.size(), folder
		)
		emitter.system.EmissionModule.enabled = emitting
		emitter.time_scale_override = float(emitter.system.simulationSpeed) * simulation_speed
		emitters.append(emitter)
		emitter.prewarm_source()
	_last_canvas_z = _effective_canvas_z()


func _process(_delta: float) -> void:
	# Existing particles must follow runtime changes to the host's Z as well
	# as newly spawned particles. Normal frames do not walk the particle list.
	var current_z := _effective_canvas_z()
	if current_z == _last_canvas_z:
		return
	_last_canvas_z = current_z
	for emitter: Node in emitters:
		var renderer: Dictionary = emitter.data.renderer
		var order := _particle_sort_order([renderer.m_SortingLayer, renderer.m_SortingOrder])
		for particle: Dictionary in emitter.particles:
			particle.visual.z_index = order


func _register_sort_key(order: Array) -> void:
	var key := Vector2i(int(order[0]), int(order[1]))
	if not key in _sort_keys:
		_sort_keys.append(key)


func _local_sort_order(order: Array) -> int:
	return _sort_keys.find(Vector2i(int(order[0]), int(order[1])))


func _particle_sort_order(order: Array) -> int:
	# The shared emitter uses top-level sprites with absolute Z. Include the
	# host's effective Z so assigning this device to a foreground layer works.
	return clampi(_effective_canvas_z() + _local_sort_order(order), -4096, 4096)


func _effective_canvas_z() -> int:
	var inherited := 0
	var item: CanvasItem = self
	while item != null:
		inherited += item.z_index
		if not item.z_as_relative:
			break
		item = item.get_parent() as CanvasItem
	return inherited


func activate() -> void:
	emitting = true


func deactivate() -> void:
	# Existing particles finish naturally; changing emission never kills them.
	emitting = false


func toggle() -> void:
	emitting = not emitting
