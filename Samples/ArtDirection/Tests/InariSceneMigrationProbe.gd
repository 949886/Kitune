extends SceneTree
## Compare legacy source conversion and authored scene loading with animation,
## physics and shader time held constant. Also exercises water-view registration.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Lab = preload("res://Samples/ArtDirection/ArtDirectionLab.tscn")
const Capture = preload("res://Samples/ArtDirection/Tools/ViewportCapture.gd")
const RECIPE := "res://Samples/ArtDirection/Tools/inari_scene_selection.json"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab: Node = Lab.instantiate()
	root.add_child(lab)
	for original: Dictionary in Assets.read_json(RECIPE):
		var index := -1
		for i in lab.profiles.size():
			if lab.profiles[i].id == original.id:
				index = i
		assert(index >= 0)
		var authored: Dictionary = lab.profiles[index].duplicate(true)
		var states: Array[Dictionary] = []
		var images: Array[Image] = []
		for profile: Dictionary in [original, authored]:
			seed(0)
			lab.profiles[index] = profile.duplicate(true)
			lab.load_level(index)
			lab.stage.process_mode = Node.PROCESS_MODE_DISABLED
			lab.player.process_mode = Node.PROCESS_MODE_DISABLED
			lab.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
			lab.stage.lighting._process(0.0)
			for visual: CanvasItem in lab.find_children("*", "CanvasItem", true, false):
				var material := visual.material as ShaderMaterial
				if material == null:
					continue
				for uniform: Dictionary in material.shader.get_shader_uniform_list():
					if uniform.name in ["uv_effect_time", "water_time"]:
						material.set_shader_parameter(uniform.name, 0.0)
			for frame in 4:
				await process_frame
			var state := {
				"spawn": lab.player.position,
				"camera": lab.camera.global_position,
				"zoom": lab.camera.zoom,
				"solids": lab.stage.solid_count,
				"enemies": lab.stage.enemies.size(),
				"wind": lab.stage.wind_triggers.size(),
				"visuals": lab.stage.visual_instances.size(),
				"tracks": lab.stage.animation.tracks.size(),
			}
			states.append(state)
			if is_instance_valid(lab.water_capture):
				for pair: Dictionary in lab.water_capture.stage_pairs:
					assert(pair.copy.current_sprite == pair.source.current_sprite)
					assert(pair.copy.modulate == pair.source.modulate)
					assert(pair.copy.transform == pair.source.transform)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var image: Image = Capture.for_png(
					lab.viewport.get_texture().get_image(), lab.viewport.use_hdr_2d
				)
				images.append(image)
				var label := "scene" if profile.has("stage_scene") else "source"
				assert(
					(
						image.save_png(
							(
								"res://tmp/art-direction/inari-migration-"
								+ original.id
								+ "-"
								+ label
								+ ".png"
							)
						)
						== OK
					)
				)
		assert(
			states[0] == states[1], "Authored loading changed native camera/content: " + str(states)
		)
		if not images.is_empty():
			var a := images[0].get_data()
			var b := images[1].get_data()
			assert(a.size() == b.size())
			var changed := 0
			var total_error := 0
			var maximum := 0
			for pixel in range(0, a.size(), 4):
				var difference := 0
				for channel in 3:
					var value := absi(a[pixel + channel] - b[pixel + channel])
					difference = maxi(difference, value)
					total_error += value
				maximum = maxi(maximum, difference)
				changed += int(difference > 1)
			print(
				"INARI_SCENE_MIGRATION_GPU ",
				original.id,
				" changed=",
				changed,
				" total_error=",
				total_error,
				" max_byte=",
				maximum
			)
			# Tiny transform serialization differences can affect raster edges. An
			# actual material, layer-order or projection change affects far more pixels.
			assert(changed <= 5 and total_error <= 100, "Inspect scene migration pixel differences")
		print("INARI_SCENE_MIGRATION_STATE ", original.id, " ", states[1])
	lab.queue_free()
	await process_frame
	print("INARI_SCENE_MIGRATION_PASS")
	quit()
