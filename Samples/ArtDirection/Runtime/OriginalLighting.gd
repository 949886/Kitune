extends Node
## Reuse source point-light falloff, layer targeting and default exposure.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const LitShader = preload("res://Samples/ArtDirection/Shaders/OriginalLit.gdshader")
const ExposureShader = preload("res://Samples/ArtDirection/Shaders/OriginalExposure.gdshader")
const DisplayShader = preload("res://Samples/ArtDirection/Shaders/OriginalDisplay.gdshader")
const PIXELS_PER_UNIT := 16.0

var settings: Dictionary
var source_lights: Array = []
var layers: Dictionary = {}
var material_variants: Dictionary = {}
var projection: Node
var last_center := Vector2.INF
var falloff: Texture2D
var exposure_material := ShaderMaterial.new()
var linear_framebuffer := false
var exposure_screen: ColorRect
var runtime_lights: Array = []
var last_runtime_revision := -1
var last_distance := -1.0


func configure(
	stage_data: Dictionary,
	source_projection: Node,
	water_capture := false,
	shared_runtime_lights: Array = []
) -> void:
	settings = Assets.read_json(Assets.ROOT + "lighting.json")
	# Preserve radiance above white for subsequent post-processing. Compatibility
	# has no HDR 2D target, so its shaders keep the explicit sRGB conversion path.
	linear_framebuffer = (
		not water_capture
		and RenderingServer.get_current_rendering_method() in [&"forward_plus", &"mobile"]
	)
	get_viewport().use_hdr_2d = linear_framebuffer
	projection = source_projection
	process_priority = 410
	falloff = load(Assets.ROOT + settings.falloff_texture)

	# This build uses unmasked multiplicative styles. Fail explicitly if a new
	# source renderer needs additive/subtractive styles rather than misreading it.
	for style: Dictionary in settings.blend_styles:
		assert(style.blendMode == 1 and style.maskTextureChannel == 0)
	for light: Dictionary in stage_data.lights:
		if light.type == 3:
			source_lights.append(light)
	# Reserve runtime rows before materials are cloned for animated enemies.
	# The water view shares these records but projects them through its own camera.
	runtime_lights = shared_runtime_lights
	source_lights.append_array(runtime_lights)
	source_lights.sort_custom(
		func(a: Dictionary, b: Dictionary): return a.settings.order < b.settings.order
	)

	var brightness: Dictionary = settings.brightness
	exposure_material.shader = ExposureShader
	exposure_material.set_shader_parameter("linear_framebuffer", linear_framebuffer)
	exposure_material.set_shader_parameter(
		"exposure_stops",
		(brightness.default_slider + brightness.exposure_offset) * brightness.exposure_scale
	)
	var output := CanvasLayer.new()
	output.layer = 1
	var screen := ColorRect.new()
	exposure_screen = screen
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.material = exposure_material
	add_child(output)
	if not water_capture:
		# A prior Ground2 snapshot is intentionally incomplete. Exposure must
		# refresh the screen copy after foreground actors have also been drawn.
		var completed_scene := BackBufferCopy.new()
		completed_scene.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		output.add_child(completed_scene)
		screen.visibility_changed.connect(func(): completed_scene.visible = screen.visible)
	output.add_child(screen)
	# WaterTextureFeature draws into an ARGB32 target before post-processing.
	# Brightness and bloom belong to the final gameplay camera only.
	screen.visible = not water_capture


func display_material(destination: Viewport) -> ShaderMaterial:
	if not linear_framebuffer or destination.use_hdr_2d:
		return null

	# An HDR SubViewport texture stores linear values. The surrounding gallery
	# renders in sRGB, so encode only when presenting the completed game image.
	var material := ShaderMaterial.new()
	material.shader = DisplayShader
	return material


func apply_to(visual: CanvasItem, item: Dictionary) -> void:
	var material_info := Assets.material_info(item.get("material", ""))
	apply_source(visual, material_info, int(item.get("layer_id", 0)), str(item.get("material", "")))


func apply_source(
	visual: CanvasItem, material_info: Dictionary, layer_id: int, material_key: String
) -> void:
	# Particle materials come from the effect bundle rather than the scene atlas.
	# Both sources use the same layer lighting and emission conversion.
	var shader_name: String = material_info.get("shader", "")
	if not ("Urp2dRenderer" in shader_name or "Sprite-Lit-Default" in shader_name):
		return
	if (
		"GLOWLIGHT_ON" in material_info.keywords
		and material_info.get("lighting_mask") == null
		and material_info.get("lighting_mask_texture") == null
	):
		# This special core also warps its mask UVs. Keep its surface conversion
		# until that spatial mask and the corresponding UV effects are reconstructed.
		return

	if not layers.has(layer_id):
		_create_layer(layer_id)
	var key := str(layer_id) + ":" + material_key
	if not material_variants.has(key):
		var material: ShaderMaterial = layers[layer_id].material.duplicate()
		if "AllIn1" in shader_name:
			MaterialSettings.configure(material, material_info, linear_framebuffer)
			material.set_shader_parameter(
				"glow_affects_light", "GLOWLIGHT_ON" in material_info.keywords
			)
			material.set_shader_parameter("lit_amount", material_info.get("lit_amount", 1.0))
			var mask: Variant = material_info.get("lighting_mask")
			if mask == null:
				mask = [1.0, 1.0, 1.0]
			material.set_shader_parameter("lighting_mask", Vector3(mask[0], mask[1], mask[2]))
			var texture_info: Variant = material_info.get("lighting_mask_texture")
			if texture_info != null:
				assert(int(texture_info.filter) == 0, "The source rifle mask is point-sampled")
				material.set_shader_parameter(
					"lighting_mask_texture", load(Assets.ROOT + texture_info.path)
				)
				material.set_shader_parameter("lighting_mask_textured", true)
				material.set_shader_parameter(
					"lighting_mask_srgb", int(texture_info.color_space) == 1
				)
		material_variants[key] = material
	visual.material = material_variants[key]
	if visual.has_method("refresh_perspective_material"):
		visual.refresh_perspective_material()


func _create_layer(layer_id: int) -> void:
	var ambient := Color.BLACK
	var has_global := false
	# URP selects the first matching global light; overlapping globals do not add.
	for light: Dictionary in settings.global_lights:
		if _affects_layer(light, layer_id):
			ambient = Assets.color(light.color) * float(light.energy)
			has_global = true
			break

	var lights: Array = []
	for light: Dictionary in source_lights:
		if _affects_layer(light, layer_id):
			lights.append(light)
	if not has_global and lights.is_empty():
		# URP returns the original surface color when no light style targets a layer.
		ambient = Color.WHITE

	var buffer := Image.create(4, maxi(lights.size(), 1), false, Image.FORMAT_RGBAF)
	var texture := ImageTexture.create_from_image(buffer)
	var material := ShaderMaterial.new()
	material.shader = LitShader
	material.set_shader_parameter("linear_framebuffer", linear_framebuffer)
	material.set_shader_parameter("ambient", Vector3(ambient.r, ambient.g, ambient.b))
	material.set_shader_parameter("light_count", lights.size())
	material.set_shader_parameter("light_data", texture)
	material.set_shader_parameter("falloff_lookup", falloff)
	layers[layer_id] = {
		"lights": lights, "buffer": buffer, "texture": texture, "material": material
	}
	_update_layer(layers[layer_id], projection.view_center)


func _affects_layer(light: Dictionary, layer_id: int) -> bool:
	# JSON numbers are floats; Array.has() distinguishes them from integer IDs.
	return layer_id in PackedInt64Array(light.layers)


func _process(_delta: float) -> void:
	var center: Vector2 = projection.view_center
	var revision := 0
	for light: Dictionary in runtime_lights:
		revision += int(light.revision)
	if (
		center.is_equal_approx(last_center)
		and revision == last_runtime_revision
		and is_equal_approx(last_distance, projection.distance)
	):
		return
	last_center = center
	last_distance = projection.distance
	last_runtime_revision = revision
	for layer: Dictionary in layers.values():
		_update_layer(layer, center)


func _update_layer(layer: Dictionary, center: Vector2) -> void:
	for index in layer.lights.size():
		var light: Dictionary = layer.lights[index]
		var spatial: Dictionary = light.spatial
		var transform := Assets.matrix(spatial.transform)
		var depth: float = projection.distance + float(spatial.depth)
		var factor: float = projection.distance / depth if depth > projection.near_clip else 0.0
		var position := center + (transform.origin - center) * factor
		var tuning: Dictionary = light.settings
		var rotation := transform.get_rotation()
		var radiance := Assets.color(light.color) * float(light.energy) * float(light.color[3])
		if not light.get("enabled", true):
			radiance = Color(0, 0, 0, 0)

		# Point-light radius ignores Transform scale in the shipped URP renderer.
		layer.buffer.set_pixel(
			0,
			index,
			Color(
				position.x,
				position.y,
				float(light.radius) * factor,
				float(tuning.inner_radius) * PIXELS_PER_UNIT * factor
			)
		)
		layer.buffer.set_pixel(1, index, Color(radiance.r, radiance.g, radiance.b, tuning.falloff))
		layer.buffer.set_pixel(
			2,
			index,
			Color(
				cos(rotation),
				sin(rotation),
				float(tuning.inner_angle) / 360.0,
				float(tuning.outer_angle) / 360.0
			)
		)
		layer.buffer.set_pixel(
			3,
			index,
			Color(
				float(tuning.normal_distance) * PIXELS_PER_UNIT * factor,
				tuning.normal_quality,
				tuning.overlap,
				0.0
			)
		)
	layer.texture.update(layer.buffer)
