extends Node
## Source-position adapter; the persistent lab owns the mixer across room loads.
const Zone = preload("res://Samples/INARIMechanisms/Devices/EnvironmentAudio/AudioParameterZone.gd")
const Location = preload("res://Samples/INARIMechanisms/PackageLocation.gd")
var zones: Array[Area2D] = []


func configure(stage: Node2D, player: Node2D, mixer: Node, loading: Callable) -> void:
	var folder: String = (Location as Script).resource_path.get_base_dir()
	for row: Dictionary in mixer.document.levels.get(stage.data.source, []):
		var zone := Zone.new()
		zone.actor_layers = player.collision_layer
		zone.settings = load(folder + "/Devices/EnvironmentAudio/Presets/" + stage.data.source + "_" + str(row.source.component_id) + ".tres")
		zone.transform = zone.settings.source_transform
		zone.set_meta("source_component", int(row.source.component_id))
		zone.bind_actor(player, loading)
		zone.bind_audio(mixer)
		stage.add_child(zone)
		zones.append(zone)
