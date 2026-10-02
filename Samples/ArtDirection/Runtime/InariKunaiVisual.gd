extends Sprite2D
## ShurikenObject's referenced sprite and material, independent of flight physics.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const GlowShader = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")

var renderer: Dictionary


func _ready() -> void:
	renderer = Assets.read_json(Assets.ROOT + "kunai_rendering.json")
	texture = load(Assets.ROOT + renderer.sprite.path)
	centered = false
	offset = Assets.vec(renderer.sprite.offset)
	flip_h = renderer.flip[0]
	flip_v = renderer.flip[1]
	texture_filter = TEXTURE_FILTER_NEAREST if int(renderer.filter) == 0 else TEXTURE_FILTER_LINEAR
	z_as_relative = false
	modulate = Assets.color(renderer.color)
	apply_material(self)


func reset_pose(pixels_per_unit: float) -> void:
	# Flight resets the root transform. Restore the prefab's 0.4 scale and the
	# sprite's 8 pixels/unit conversion without changing its physical origin.
	scale = Assets.vec(renderer.prefab_scale) * pixels_per_unit / float(renderer.sprite.ppu)
	modulate = Assets.color(renderer.color)
	material.set_shader_parameter("hit_blend", renderer.material.hit_blend)


func apply_material(visual: Sprite2D, lighting: Node = null) -> void:
	var surface := ShaderMaterial.new()
	surface.shader = GlowShader
	MaterialSettings.configure(surface, renderer.material, visual.get_viewport().use_hdr_2d)
	visual.material = surface
	if is_instance_valid(lighting):
		lighting.apply_source(visual, renderer.material, int(renderer.layer_id), "kunai")
		visual.material = visual.material.duplicate()
