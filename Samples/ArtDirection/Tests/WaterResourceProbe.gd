extends SceneTree
## Build a minimal PCK without PNG source files, then load it in a separate process.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const OUTPUT := "res://tmp/art-direction/water-pack-probe/"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var project := FileAccess.open(OUTPUT + "project.godot", FileAccess.WRITE)
	project.store_string('config_version=5\n[application]\nconfig/name="Water resource probe"\n')
	project.close()
	var pack_path := OUTPUT + "water-probe.pck"
	var pack := PCKPacker.new()
	assert(pack.pck_start(pack_path) == OK)
	assert(pack.add_file("res://project.godot", OUTPUT + "project.godot") == OK)
	for relative in [
		"Runtime/OriginalWater.gd",
		"Runtime/OriginalAssets.gd",
		"Shaders/OriginalWater.gdshader",
		"Shaders/OriginalColorSpace.gdshaderinc",
		"Shaders/OriginalWaterUV.gdshaderinc",
		"Original/INARI/water.json",
		"Tests/WaterPackedProbe.gd",
	]:
		var path: String = "res://Samples/ArtDirection/" + relative
		assert(pack.add_file(path, path) == OK)
	var settings: Dictionary = Assets.read_json(Assets.ROOT + "water.json")
	for mip: Dictionary in settings.normal.mips:
		var path := Assets.ROOT + str(mip.path) + ".import"
		var options := ConfigFile.new()
		assert(options.load(path) == OK)
		assert(not options.get_value("params", "process/fix_alpha_border"))
		assert(not options.get_value("params", "mipmaps/generate"))
		assert(options.get_value("params", "compress/normal_map") == 2)
		var imported: String = options.get_value("remap", "path")
		assert(pack.add_file(path, path) == OK)
		assert(pack.add_file(imported, imported) == OK)
	assert(pack.flush() == OK)
	var output: Array = []
	var exit_code := (
		OS
		. execute(
			OS.get_executable_path(),
			PackedStringArray(
				[
					"--headless",
					"--path",
					ProjectSettings.globalize_path(OUTPUT),
					"--main-pack",
					ProjectSettings.globalize_path(pack_path),
					"--script",
					"res://Samples/ArtDirection/Tests/WaterPackedProbe.gd",
					"--quit-after",
					"120",
				]
			),
			output,
			true,
			false
		)
	)
	var log := "\n".join(output)
	assert(exit_code == 0 and "WATER_PACKED_PASS" in log, log)
	assert(not "SCRIPT ERROR:" in log and not "Failed loading resource:" in log, log)
	print("WATER_RESOURCE_PASS (isolated PCK; no original PNGs)")
	quit()
