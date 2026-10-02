extends "res://Samples/ArtDirection/Runtime/InariKunaiVisual.gd"
## A frozen sprite snapshot. Source OnEnable starts fading before fields are assigned.

const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")

var source: Dictionary
var age := 0.0


func _ready() -> void:
	source = Assets.read_json(Assets.ROOT + "kunai_afterimage.json")
	super._ready()


func configure(target: Sprite2D, stage: Node, delta: float) -> void:
	global_transform = target.global_transform
	texture = target.texture
	offset = target.offset
	centered = target.centered
	flip_h = target.flip_h
	flip_v = target.flip_v
	modulate = target.modulate
	var sort: Array = renderer.sort.duplicate()
	sort[1] += int(source.sortingOrderOffset)
	z_index = stage.sort_depth(sort)
	# AddComponent invokes OnEnable synchronously, before SpawnGhost assigns
	# startAlpha. Subsequent coroutine updates use the serialized emitter value.
	advance(delta, true)


func apply_material(visual: Sprite2D, _lighting: Node = null) -> void:
	assert(source.material.shader == "Sprites/Default")
	var surface := ShaderMaterial.new()
	surface.shader = GlowShader
	MaterialSettings.configure(surface, source.material, visual.get_viewport().use_hdr_2d)
	visual.material = surface


func advance(delta: float, first_update := false) -> void:
	if age >= float(source.life):
		hide()
		queue_free()
		return
	age = PackedFloat32Array([age + delta])[0]
	var settings: Dictionary = source.first_update_defaults if first_update else source
	var fraction := clampf(age / float(settings.life), 0.0, 1.0)
	modulate.a = float(settings.startAlpha) * SourceCurve.evaluate(source.alphaOverLife, fraction)
