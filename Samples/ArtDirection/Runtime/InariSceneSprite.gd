@tool
extends "res://Samples/ArtDirection/Runtime/OriginalSprite.gd"
## Native sprite content with an editor-visible placement. Standard Node2D pose,
## tint and visibility survive initialization; animation continues in that pose.

@export var source_item: Dictionary
@export var source_animation_enabled := true

var authored_tint_scale := Color.WHITE
var authored_tint_bias := Color(0, 0, 0, 0)


func _ready() -> void:
	if Engine.is_editor_hint() and not source_item.is_empty():
		prepare()
		set_process(false)


func prepare() -> void:
	var pose := transform
	var tint := modulate
	var shown := visible
	var item := source_item.duplicate(true)
	var original := Assets.matrix(item.transform)
	# Tilted rendering uses a separate native XY/depth transform. Carry the same
	# editor adjustment into that transform so moving a cloud moves its pixels.
	if item.has("spatial"):
		var spatial_pose := pose * original.affine_inverse() * Assets.matrix(item.spatial.transform)
		item.spatial.transform = _matrix_array(spatial_pose)
	item.transform = _matrix_array(pose)
	configure(item)
	# Derive an adjustment from the saved final tint, including channels that the
	# original material made zero. Later material animation keeps that adjustment.
	for channel in 4:
		if modulate[channel] != 0.0:
			authored_tint_scale[channel] = tint[channel] / modulate[channel]
		else:
			authored_tint_bias[channel] = tint[channel]
	transform = pose
	original_rotation = rotation
	modulate = tint
	visible = shown


func _configure_material(key: String) -> void:
	super._configure_material(key)
	modulate = modulate * authored_tint_scale + authored_tint_bias


static func _matrix_array(value: Transform2D) -> Array:
	return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]
