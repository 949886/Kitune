extends Node
## Native host for the portable lifecycle coordinator. Initial scene overrides
## and replacement prefab data are distinct, and each generation owns its own
## renderer nodes, animation players and mutable materials.
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Enemy = preload("res://Samples/ArtDirection/Runtime/OriginalEnemy.gd")
const Visual = preload("res://Samples/ArtDirection/Runtime/OriginalSprite.gd")
const SourceAnimation = preload("res://Samples/ArtDirection/Runtime/OriginalSceneAnimation.gd")
const Device = preload("res://Samples/INARIMechanisms/Devices/RepeatingSpawner/RepeatingSpawner.tscn")
var stage: Node2D
var player: CharacterBody2D
var source: Dictionary
var device: Node2D
var actors: Dictionary = {}
var replacement_count := 0
var persistence_removals := 0


func configure(owner_stage: Node2D, target: CharacterBody2D, record: Dictionary) -> void:
	stage = owner_stage
	player = target
	source = record
	assert(stage.data.source == source.record.scene)
	device = Device.instantiate()
	device.settings = device.settings.duplicate(true)
	# The exported placements are relative to the original spawner transform.
	device.position = Assets.vec(source.record.source_origin)
	add_child(device)
	device.flags_requested.connect(func(actor, repeated, loaded):
		actor.set_meta("is_repeated", repeated)
		actor.set_meta("is_loaded", loaded))
	device.member_registered.connect(_registered)
	device.member_unregistered.connect(func(_key, actor): stage.enemies.erase(actor))
	# The demo has no global enemy persistence database. Forward/observe this
	# event without inventing a save record; the portable host owns storage.
	device.persistence_remove_requested.connect(func(_actor): persistence_removals += 1)
	for member: Dictionary in source.record.members:
		device.register_factory(member.kind, _replacement)
		var original: Dictionary = source.variants.initial.enemies[0]
		var actor := _create_actor(source.variants.initial, Assets.vec(original.position))
		actors[member.key] = actor
		_connect_death(member.key, actor)
		device.bind_enemy(member.key, actor, actor.force_repeat_idle, actor.apply_repeat_tint)


func _replacement(point: Vector2) -> Dictionary:
	var actor := _create_actor(source.variants.replacement, point)
	return {"actor": actor, "idle": actor.force_repeat_idle, "tint": actor.apply_repeat_tint}


func _registered(key: StringName, actor: Node2D) -> void:
	replacement_count += 1
	actors[String(key)] = actor
	_connect_death(key, actor)


func _connect_death(key: StringName, actor: Node2D) -> void:
	actor.defeated.connect(func(): device.notify_defeated(key, actor))


func _create_actor(variant: Dictionary, point: Vector2) -> CharacterBody2D:
	var data: Dictionary = variant.enemies[0].duplicate(true)
	var offset := point - Assets.vec(data.position)
	data.position = [point.x, point.y]
	data.gfx_position[0] += offset.x
	data.gfx_position[1] += offset.y
	data.weakpoint_binding.range_transform[4] += offset.x
	data.weakpoint_binding.range_transform[5] += offset.y
	var actor := Enemy.new()
	stage.add_child(actor)
	var artwork := Node2D.new()
	artwork.name = "SourceArtwork"
	# Source visuals use world transforms, while actor motion writes their
	# global poses. Top-level ownership avoids applying actor motion twice.
	artwork.top_level = true
	actor.add_child(artwork)
	var visuals := {}
	for source_item: Dictionary in variant.sprites:
		var item: Dictionary = source_item.duplicate(true)
		item.transform[4] += offset.x
		item.transform[5] += offset.y
		var visual := Visual.new()
		artwork.add_child(visual)
		visual.configure(item)
		visual.z_index = stage.sort_depth(item.sort)
		stage.lighting.apply_to(visual, item)
		visual.animation_material_changed.connect(stage._on_animation_material_changed.bind(visual))
		visuals[item.go] = visual
	var animation := SourceAnimation.new()
	actor.add_child(animation)
	animation.configure(variant.animations, visuals)
	actor.configure(data, visuals, animation, stage.navigation, stage.sort_depth)
	actor.ranged_combat.target = player
	stage.combat_clock.subscribe(actor)
	stage.enemies.append(actor)
	return actor


func before_scene_changed() -> void:
	device.before_scene_changed()
