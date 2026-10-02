extends Node2D
## Native DrawAimLineForGamepad: free ray, short-hit suppression and enemy endpoint.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const LineShader = preload("res://Samples/ArtDirection/Shaders/OriginalDottedLine.gdshader")

var actor: CharacterBody2D
var settings: Dictionary
var line := Line2D.new()
var pointer := Visual.new()
var holder_position := Vector2.ZERO
var pointer_basis := Transform2D.IDENTITY


func configure(owner_node: CharacterBody2D, stage: Node) -> void:
	actor = owner_node
	settings = Assets.read_json(Assets.ROOT + "gamepad_aim.json")
	top_level = true
	pointer.configure(settings.pointer)
	pointer_basis = pointer.transform
	add_child(pointer)
	pointer.z_as_relative = false
	pointer.z_index = stage.sort_depth(settings.pointer.sort)
	stage.lighting.apply_to(pointer, settings.pointer)
	add_child(line)
	line.z_as_relative = false
	line.z_index = stage.sort_depth(settings.line.sort)
	line.texture = load(Assets.ROOT + settings.line.texture.path)
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var parameters: Dictionary = settings.line.parameters
	assert(parameters.widthCurve.m_Curve.size() == 1)
	assert(parameters.colorGradient.key0 == parameters.colorGradient.key1)
	# World-space LineRenderer vertices and width are independent of its 0.7 TRS scale.
	line.width = (
		float(parameters.widthMultiplier)
		* float(parameters.widthCurve.m_Curve[0].value)
		* actor.units
	)
	var material := ShaderMaterial.new()
	material.shader = LineShader
	material.set_shader_parameter("linear_framebuffer", stage.lighting.linear_framebuffer)
	material.set_shader_parameter("line_color", Assets.color(settings.line.color))
	var gradient: Dictionary = parameters.colorGradient.key0
	material.set_shader_parameter(
		"gradient_color", Color(gradient.r, gradient.g, gradient.b, gradient.a)
	)
	material.set_shader_parameter("dash_length", settings.line.dash_length)
	material.set_shader_parameter("gap_length", settings.line.gap_length)
	material.set_shader_parameter("pixels_per_unit", actor.units)
	line.material = material
	hide()


func update_aim(targeting: RefCounted) -> void:
	if (
		not targeting.using_gamepad
		or (targeting.aim_until <= actor.clock and not is_instance_valid(targeting.snap_target))
	):
		hide()
		return
	show()
	var direction: Vector2 = targeting.throw_direction()
	var body_offset: Dictionary = actor.tuning.body_offset
	var origin: Vector2 = actor.global_position + actor.body_shape.position
	origin -= Vector2(body_offset.x, -float(body_offset.y)) * actor.units
	holder_position = origin + Assets.vec(settings.holder_offset)
	var start := holder_position + Assets.vec(settings.line.offset).rotated(direction.angle())
	var end: Vector2
	var color_key := "free"
	if is_instance_valid(targeting.snap_target):
		var target: Node2D = targeting.snap_target
		end = target.global_position + target.body_shape.position
		pointer.show()
		color_key = "enemy"
	else:
		var distance: float = float(actor.combat.ShurikenMaxDistance) * actor.units
		var ray := PhysicsRayQueryParameters2D.create(
			holder_position, holder_position + direction * distance, Collision.SIGHT_SURFACE
		)
		var hit := actor.get_world_2d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			end = start + direction * distance
			pointer.hide()
		elif (
			holder_position.distance_to(hit.position)
			> float(settings.minimum_hit_distance) * actor.units
		):
			end = hit.position
			pointer.show()
		else:
			end = start
			pointer.hide()
	line.global_position = start
	line.points = PackedVector2Array([Vector2.ZERO, end - start])
	pointer.global_transform = Transform2D(direction.angle(), end) * pointer_basis
	pointer.modulate = Assets.color(settings.pointer_colors[color_key])
