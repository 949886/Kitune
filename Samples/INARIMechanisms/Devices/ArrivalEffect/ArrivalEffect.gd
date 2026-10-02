@tool
extends Node2D
## Actual prefab hierarchy and streamed/constant Animator channels. The effect
## has no enemy or wave timer; the coordinator separately reveals its actors.
signal animation_completed
signal light_state_changed(states: Array)
const Location = preload("../../PackageLocation.gd")
const Sprite = preload("../../Core/DeviceSprite.gd")
const Tiled = preload("ArrivalTiledSprite.gd")
const Emitter = preload("../../Core/DeviceEmitter.gd")
const Audio = preload("../../Core/DeviceAudio.gd")
const MaskShader = preload("MaskedArrival.gdshader")
@export_enum("SpawnStamp", "SpawnRope") var source_asset := "SpawnStamp"
@export_range(0, 5, 0.01, "or_greater") var custom_time_scale := 1.0
@export var play_audio := true
@export var random_seed := 17
@export_flags_2d_physics var particle_collision_mask := 1
var document: Dictionary
var nodes: Dictionary = {}
var visuals: Dictionary = {}
var emitters: Array[Node] = []
var light_states: Array = []
var masked: Array[Dictionary] = []
var audio: Node
var elapsed := 0.0
var completed := false
var destroy_on_completion := false
var sorting: Callable = _particle_sort
var _sort_keys: Array[Vector2i] = []


func _ready() -> void:
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/" + source_asset + "/"
	document = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	var ambient: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "ambient.json"))
	for row: Dictionary in document.nodes:
		var node := Node2D.new()
		node.name = str(row.go) + "_" + str(row.name)
		if row.parent == null: add_child(node)
		else: nodes[int(row.parent)].add_child(node)
		node.position = Vector2(row.position[0], -row.position[1]) * 16.0
		node.rotation = float(row.rotation)
		node.scale = Vector2(row.scale[0], row.scale[1])
		node.visible = row.active
		nodes[int(row.go)] = node
	for record: Dictionary in document.sprites:
		_add_sort(record.renderer_order)
	for record: Dictionary in ambient.emitters:
		_add_sort([record.renderer.m_SortingLayer, record.renderer.m_SortingOrder])
	_sort_keys.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	for record: Dictionary in document.sprites:
		var visual: Node2D = Tiled.new() if int(record.mode) != 0 else Sprite.new()
		nodes[int(record.go)].add_child(visual)
		visual.configure(record.duplicate(true), document.sprite_info[record.sprite], folder)
		visual.sprite_library = document.sprite_info
		visual.z_index = _rank(record.renderer_order)
		visuals[int(record.go)] = visual
		for mask: Dictionary in document.masks:
			var order: Array = record.renderer_order
			var fields: Dictionary = mask.fields
			if int(record.mask_interaction) != 2 or int(order[0]) != int(fields.m_BackSortingLayer) or int(order[1]) < int(fields.m_BackSortingOrder) or int(order[1]) > int(fields.m_FrontSortingOrder):
				continue
			assert(fields.m_IsCustomRangeActive and fields.m_FrontSortingLayer == fields.m_BackSortingLayer)
			var material: ShaderMaterial = visual.material
			material.shader = MaskShader
			material.set_shader_parameter("mask_texture", load(folder + document.sprite_info[mask.sprite].path))
			material.set_shader_parameter("mask_cutoff", fields.m_MaskAlphaCutoff)
			masked.append({"visual": visual, "definition": mask, "material": material})
	light_states = document.lights.duplicate(true)
	_sample(0)
	if Engine.is_editor_hint():
		set_process(false)
		return
	for record: Dictionary in ambient.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		var local := record.duplicate(true)
		# Parent-local frame follows all animated ancestors. The emitter itself
		# remains owned by the effect so top-level particles leave with it.
		local.transform = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
		var frame: Node2D = nodes[int(record.go)]
		emitter.frame_transform = func(): return frame.global_transform
		emitter.configure_source(local, self, document.gravity, random_seed + emitters.size(), folder)
		emitter.collision_mask = particle_collision_mask
		emitter.set_animation_visibility(frame.is_visible_in_tree())
		emitters.append(emitter)
	audio = Audio.new()
	audio.folder = folder
	audio.groups = document.audio
	add_child(audio)
	if play_audio: audio.play_event(str(document.audio.keys()[0]), self)
	destroy_on_completion = document.clip.destroy_state in [document.clip.state_name, document.clip.state_path]


func _add_sort(order: Array) -> void:
	var key := Vector2i(int(order[0]), int(order[1]))
	if not key in _sort_keys: _sort_keys.append(key)


func _rank(order: Array) -> int:
	return _sort_keys.find(Vector2i(int(order[0]), int(order[1])))


func _particle_sort(order: Array) -> int:
	var total := _rank(order)
	var item: CanvasItem = self
	while item != null:
		total += item.z_index
		if not item.z_as_relative: break
		item = item.get_parent() as CanvasItem
	return clampi(total, -4096, 4096)


func _process(delta: float) -> void:
	advance_animation(delta)


func advance_animation(delta: float) -> void:
	if completed: return
	elapsed += delta * custom_time_scale * float(document.clip.speed)
	_sample(minf(elapsed, float(document.clip.length)))
	for emitter: Node in emitters:
		emitter.set_animation_visibility(nodes[int(emitter.data.go)].is_visible_in_tree())
	# EnemySpawnStamp waits until normalizedTime > 1, not >= 1. Keep the
	# mismatched stamp state name: its GameObject survives the final pose.
	if elapsed > float(document.clip.length):
		completed = true
		animation_completed.emit()
		if destroy_on_completion: queue_free()


func _sample(time: float) -> void:
	for track: Dictionary in document.tracks:
		var node: Node2D = nodes[int(track.go)]
		var values: Array = track.curves.map(func(keys): return _curve(keys, time))
		match track.property:
			"position": node.position = Vector2(values[0], -values[1]) * 16.0
			"rotation": node.rotation = -deg_to_rad(values[2])
			"scale": node.scale = Vector2(values[0], values[1])
			"active": node.visible = values[0] >= 0.5
			"alpha": visuals[int(track.go)].modulate.a = values[0]
			"size_y": visuals[int(track.go)].set_source_height(values[0])
			"light_energy":
				for light: Dictionary in light_states:
					if int(light.go) == int(track.go): light.fields.m_Intensity = values[0]
			"sprite":
				var key = track.frames[0][1]
				for frame: Array in track.frames:
					if float(frame[0]) > time: break
					key = frame[1]
				visuals[int(track.go)].set_animation_sprite(key)
	_update_masks()
	for light: Dictionary in light_states:
		var node: Node2D = nodes[int(light.go)]
		light.world_transform = node.global_transform
		light.active = node.is_visible_in_tree()
	light_state_changed.emit(light_states.duplicate(true))


func _update_masks() -> void:
	for binding: Dictionary in masked:
		var node: Node2D = nodes[int(binding.definition.go)]
		var active := node.is_visible_in_tree() and not is_zero_approx(node.global_transform.determinant())
		binding.material.set_shader_parameter("mask_enabled", active)
		if not active: continue
		var info: Dictionary = document.sprite_info[binding.definition.sprite]
		var pose: Transform2D = node.global_transform.affine_inverse() * binding.visual.global_transform
		var units := float(info.ppu) / 16.0
		binding.material.set_shader_parameter("mask_x", Vector3(pose.x.x * units, pose.y.x * units, pose.origin.x * units - float(info.offset[0])) / float(info.size[0]))
		binding.material.set_shader_parameter("mask_y", Vector3(pose.x.y * units, pose.y.y * units, pose.origin.y * units - float(info.offset[1])) / float(info.size[1]))


static func _curve(keys: Array, time: float) -> float:
	var key: Array = keys[0]
	for candidate: Array in keys:
		if float(candidate[0]) > time: break
		key = candidate
	var t := maxf(0, time - float(key[0]))
	var c: Array = key[1]
	return ((float(c[0]) * t + float(c[1])) * t + float(c[2])) * t + float(c[3])
