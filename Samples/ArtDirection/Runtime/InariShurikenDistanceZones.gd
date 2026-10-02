extends Node
## Native actor adapter. Presets use complete source geometry; the host owns
## the current player and the shared range state, with no global singleton.
const Zone = preload("res://Samples/INARIMechanisms/Devices/ShurikenDistance/ShurikenDistanceZone.gd")
const Location = preload("res://Samples/INARIMechanisms/PackageLocation.gd")
var zones: Array[Area2D] = []


func configure(stage: Node2D, player: Node2D, loading: Callable) -> void:
	var folder: String = (Location as Script).resource_path.get_base_dir()
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/ShurikenDistance/device.json"))
	for id: String in evidence.records:
		if id.get_slice("_", 0) != stage.data.source: continue
		var zone := Zone.new()
		zone.settings = load(folder + "/Devices/ShurikenDistance/Presets/" + id + ".tres")
		zone.transform = zone.settings.source_transform
		zone.actor_layers = player.collision_layer
		zone.bind_actor(player, loading)
		zone.bind_range(player.shuriken_range)
		stage.add_child(zone)
		zones.append(zone)
