@tool
extends Node2D
## A Unity SpriteRenderer, including pivot, tiling, tint and flips.

signal animation_material_changed(key: String)
signal animation_pose_changed

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const GlowShader = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const Water = preload("res://Samples/ArtDirection/Runtime/OriginalWater.gd")
const TiltedSprite = preload("res://Samples/ArtDirection/Runtime/OriginalTiltedSprite.gd")
const Slicing = preload("res://Samples/ArtDirection/Runtime/OriginalSpriteSlicing.gd")

var data: Dictionary
var source: Texture2D
var destination: Rect2
var is_water := false
var rotation_speed := 0.0
var original_rotation := 0.0
var elapsed := 0.0
var animation_rotation := 0.0
var current_sprite = null
var effect_mesh: Dictionary = {}
var effect_texture: Texture2D
var current_material := ""
var animation_offset := Vector2.ZERO
var animation_visibility: Variant = null
var perspective: RefCounted
var slice_quads: Array[Rect2] = []


func configure_perspective(spatial: Dictionary, projection: Node) -> void:
	perspective = TiltedSprite.new()
	perspective.configure(spatial, projection)
	refresh_perspective_material()
	queue_redraw()


func refresh_perspective_material() -> void:
	if perspective != null:
		if material == null:
			# Native custom materials without a port still need projective sampling
			# for tilted geometry. Preserve their existing renderer tint; effects
			# such as RotatingCog blur remain tracked as unsupported material work.
			var projected := ShaderMaterial.new()
			projected.shader = GlowShader
			projected.set_shader_parameter("linear_framebuffer", get_viewport().use_hdr_2d)
			material = projected
		assert(material is ShaderMaterial, "Tilted source sprites require projective UV sampling")
		material = material.duplicate()
		queue_redraw()


func _enter_tree() -> void:
	if material is ShaderMaterial and (material.shader == GlowShader or is_water):
		material.set_shader_parameter("linear_framebuffer", get_viewport().use_hdr_2d)


func configure(item: Dictionary) -> void:
	data = item
	visible = item.get("visible", true)
	set_animation_sprite(item.sprite)

	transform = Assets.matrix(item.transform)
	original_rotation = rotation
	modulate = Assets.color(item.color)
	_configure_material(item.get("material", ""))
	queue_redraw()


func _configure_material(key: String) -> void:
	current_material = key
	material = null
	is_water = false
	rotation_speed = 0.0
	modulate = Assets.color(data.color)
	if data.blend == "add":
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive

	# Translate only supported material effects; a black glow mask emits nothing.
	var source_material := Assets.material_info(key)
	if not source_material.is_empty():
		var custom_sprite_shader: bool = "AllIn1" in source_material.shader
		if not custom_sprite_shader:
			modulate *= Assets.color(source_material.color)
			modulate.a *= float(source_material.alpha)
		is_water = "Shader_Water" in str(source_material.shader)
		if source_material.shader == "Custom/RotatingCog":
			# The shipped shader property is degrees/sec. Reverse its sign for Y-down.
			rotation_speed = -deg_to_rad(float(source_material.rotation_speed))

		if is_water:
			var water := ShaderMaterial.new()
			water.shader = Water.WaterShader
			Water.configure(water, is_inside_tree() and get_viewport().use_hdr_2d)
			material = water
			# Water's source sprite is one pixel. Unpack it so the shader receives
			# the complete 0..1 quad UV range rather than atlas coordinates.
			source = ImageTexture.create_from_image(source.get_image())
		elif custom_sprite_shader:
			var glow := ShaderMaterial.new()
			glow.shader = GlowShader
			MaterialSettings.configure(
				glow, source_material, is_inside_tree() and get_viewport().use_hdr_2d
			)
			material = glow

	set_process(not is_zero_approx(rotation_speed))
	_apply_source_sampler()
	queue_redraw()


func set_animation_material(key: String) -> void:
	if key == current_material:
		return
	_configure_material(key)
	animation_material_changed.emit(key)


func set_animation_visibility(value: bool) -> void:
	animation_visibility = value
	visible = value
	animation_pose_changed.emit()


func set_animation_offset(value: Vector2) -> void:
	var difference := value - animation_offset
	animation_offset = value
	if not animation_pose_changed.get_connections().is_empty():
		# An enemy applies source offsets before mirroring its flattened subtree.
		animation_pose_changed.emit()
	else:
		global_position += difference


func reset_animation_properties(kinds: Array) -> void:
	if "position" in kinds:
		set_animation_offset(Vector2.ZERO)
	if "active" in kinds:
		animation_visibility = null
		visible = data.get("visible", true)
	if "material" in kinds:
		set_animation_material(data.get("material", ""))
	if "sprite" in kinds:
		set_animation_sprite(data.sprite)
	if "rotation" in kinds:
		set_animation_rotation(0.0)
	animation_pose_changed.emit()


func _process(delta: float) -> void:
	elapsed += delta
	if not is_zero_approx(rotation_speed):
		rotation = original_rotation + animation_rotation + elapsed * rotation_speed


func set_animation_sprite(key: Variant) -> void:
	if key == current_sprite:
		return
	current_sprite = key
	slice_quads.clear()
	source = Assets.texture(key) if key != null else null
	if source != null:
		var info := Assets.sprite_info(key)
		effect_mesh = info.get("effect_mesh", {})
		effect_texture = (
			load(Assets.ROOT + effect_mesh.texture.path) if not effect_mesh.is_empty() else null
		)
		var factor: float = 16.0 / info.ppu
		# Every original frame keeps its own trimmed rectangle and pivot.
		destination = Rect2(Assets.vec(info.offset) * factor, Assets.vec(info.size) * factor)
		if int(data.mode) != 0:
			destination = Rect2(-Assets.vec(data.size) / 2.0, Assets.vec(data.size))
			var slicing := Slicing.definition(key)
			if not slicing.is_empty() and effect_mesh.is_empty():
				destination.position = -Assets.vec(slicing.pivot) * destination.size
				slice_quads = Slicing.build(slicing, destination, factor, int(data.mode) == 2)
	_apply_source_sampler()
	queue_redraw()


func _apply_source_sampler() -> void:
	var bilinear: bool = not effect_mesh.is_empty() and int(effect_mesh.texture.filter) == 1
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR if bilinear else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	if material is ShaderMaterial and material.shader == GlowShader:
		material.set_shader_parameter("source_bilinear", bilinear)


func set_animation_rotation(angle: float) -> void:
	animation_rotation = angle
	rotation = original_rotation + animation_rotation + elapsed * rotation_speed


func _draw() -> void:
	if source == null:
		return
	if perspective != null:
		perspective.draw(self)
		return

	var flips: Array = data.flip
	draw_set_transform(
		Vector2.ZERO, 0.0, Vector2(-1.0 if flips[0] else 1.0, -1.0 if flips[1] else 1.0)
	)
	if not effect_mesh.is_empty():
		# UV deformation must sample the original texture beyond the tight mesh's
		# bounds. A masked/repacked atlas would incorrectly clip or sample neighbors.
		for triangle: Array in effect_mesh.triangles:
			var points := PackedVector2Array()
			var uv := PackedVector2Array()
			for index: int in triangle:
				points.append(Assets.vec(effect_mesh.vertices[index]))
				uv.append(Assets.vec(effect_mesh.uv[index]))
			draw_primitive(points, PackedColorArray([Color.WHITE]), uv, effect_texture)
		return
	if not slice_quads.is_empty():
		for index in range(0, slice_quads.size(), 2):
			draw_texture_rect_region(source, slice_quads[index], slice_quads[index + 1])
		return
	if int(data.mode) != 2:
		draw_texture_rect(source, destination, false)
		return

	# Crop the last tile at the renderer boundary instead of stretching its pixels.
	var size := source.get_size() * (16.0 / float(Assets.sprite_info(data.sprite).ppu))
	for y in range(ceili(destination.size.y / size.y)):
		for x in range(ceili(destination.size.x / size.x)):
			var start := Vector2(x, y) * size
			var piece := (destination.size - start).min(size)
			draw_texture_rect_region(
				source,
				Rect2(destination.position + start, piece),
				Rect2(Vector2.ZERO, piece / size * source.get_size())
			)
