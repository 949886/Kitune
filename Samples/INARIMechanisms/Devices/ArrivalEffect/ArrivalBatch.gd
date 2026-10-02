extends Node2D
## One batch matches one SpawnManager.PhaseActiveOn. Positions are world-space
## prefab origins; sort_y is the enemy's ground Y before the prefab Y offset.
const Stamp = preload("SpawnStamp.tscn")
const Rope = preload("SpawnRope.tscn")
const Location = preload("../../PackageLocation.gd")
@export var play_audio := true
@export_range(0, 5, 0.01, "or_greater") var custom_time_scale := 1.0:
	set(value):
		custom_time_scale = value
		for effect: Node in get_children(): effect.custom_time_scale = value
## Space for internal renderer ranks so one SortingGroup cannot interleave
## with another. Hosts can position the complete batch on their foreground Z.
@export var group_stride := 32
var batches_started := 0
var source_group_order: Array
var source_references: Array


func _ready() -> void:
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/SpawnStamp/"
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "device.json"))
	source_group_order = [source.sorting_group.m_SortingLayer, source.sorting_group.m_SortingOrder]
	source_references = source.spawn_references


## Native host can preserve the original GFX lossy scale, then account for
## its actor turning since import. Portable hosts normally pass the live value.
func source_gfx_scale(scene: String, spawner_go: int, member: int, facing: float) -> float:
	for record: Dictionary in source_references:
		if record.scene == scene and int(record.spawner_go) == spawner_go:
			var scale_data: Dictionary = record.member_scales[str(member)]
			return float(scale_data.gfx_scale_x) * facing / float(scale_data.facing)
	assert(false, "Native arrival must have an audited source spawner")
	return facing


func spawn_wave(members: Array) -> Array[Node2D]:
	var ordered := members.duplicate(true)
	# Unity sorts descending Y-up; Godot ground coordinates are Y-down.
	ordered.sort_custom(func(a, b): return float(a.sort_y) < float(b.sort_y))
	var effects: Array[Node2D] = []
	for index in ordered.size():
		var record: Dictionary = ordered[index]
		assert(record.kind in ["stamp", "rope"])
		var effect: Node2D = (Rope if record.kind == "rope" else Stamp).instantiate()
		effect.custom_time_scale = custom_time_scale
		effect.play_audio = play_audio
		effect.top_level = true
		effect.position = record.position
		effect.z_index = index * group_stride
		effect.set_meta("member_key", record.get("key", ""))
		var facing := float(record.get("gfx_scale_x", 1.0))
		# Mathf.Approximately(lossyScale.x, -1), not just a negative facing.
		if record.kind == "rope" and absf(facing + 1.0) < 0.000001 * maxf(1.0, absf(facing)):
			effect.scale.x = -1
		add_child(effect)
		effects.append(effect)
	batches_started += 1
	return effects
