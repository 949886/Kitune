extends RefCounted
## RotationPart's original renderer switching, strict angle thresholds and layers.

var actor: CharacterBody2D
var settings: Dictionary
var sort_depth: Callable
var aiming := false
var angle := 0.0
var pose_dirty := false


func configure(enemy: CharacterBody2D, sorting: Callable) -> void:
	actor = enemy
	settings = actor.data.get("ranged_presentation", actor.data.get("rifle_presentation", {}))
	sort_depth = sorting


func set_aiming(value: bool) -> void:
	aiming = value
	pose_dirty = true
	if not value:
		angle = 0.0
	actor._sync_visuals()


func set_angle(value: float) -> void:
	angle = value
	pose_dirty = true
	actor._sync_visuals()


func apply() -> void:
	if settings.is_empty() or actor.dead:
		return
	# Source SetRotation changes sprite references only when targeting runs.
	# Body movement must retain frames subsequently written by the shot Animator.
	var refresh_sprites := pose_dirty
	pose_dirty = false
	for go in settings.RotationHolder:
		if actor.visuals.has(go):
			actor.visuals[go].visible = aiming and _child_active(go)
	if settings.hasNonRotationHolder:
		for go in settings.NonRotationHolder:
			if actor.visuals.has(go):
				actor.visuals[go].visible = not aiming and _child_active(go)
	var delta := angle * float(settings.rotationScale) + float(settings.rotationOffset)
	for part: Dictionary in settings.RotationSpriteInfos:
		if not actor.visuals.has(part.go):
			continue
		var visual: Node2D = actor.visuals[part.go]
		# Multiply in the original local frame so a mirrored GFX subtree reverses
		# the world rotation correctly without changing the gun's pivot position.
		var rotation := -deg_to_rad(delta * float(part.scale) - float(part.initial_angle))
		visual.global_transform *= Transform2D(rotation, Vector2.ZERO)
		if not refresh_sprites:
			continue
		for info: Dictionary in part.infos:
			if float(info.angle) < delta:
				_select(visual, info)
	if not aiming or not refresh_sprites:
		return
	for part: Dictionary in settings.NonRotationHolderInfos:
		if not actor.visuals.has(part.go):
			continue
		var visual: Node2D = actor.visuals[part.go]
		visual.set_animation_sprite(part.infos[0].sprite)
		for info: Dictionary in part.infos:
			if float(info.angle) < delta:
				_select(visual, info)


func _child_active(go: Variant) -> bool:
	var animated: Variant = actor.visuals[go].animation_visibility
	return (
		animated
		if animated != null
		else settings.get("holder_defaults", {}).get(str(int(go)), true)
	)


func _select(visual: Node2D, info: Dictionary) -> void:
	visual.set_animation_sprite(info.sprite)
	if int(info.order) != 0 and sort_depth.is_valid():
		visual.z_index = sort_depth.call(info.sort)


func animation(trigger: String, index := 0, degrees := 0.0) -> Array:
	var source: Dictionary = actor.data.get("combat_animations", {}).get(
		"%s:%d" % [trigger, index], {}
	)
	if not source.has("variants"):
		return source.get("tracks", [])
	# Sprite references are discrete properties. Select the dominant child of
	# the source 1D angle blend, retaining its own frame timestamps and speed.
	var selected: Dictionary = source.variants[0]
	var distance := absf(degrees - float(selected.threshold))
	for variant: Dictionary in source.variants:
		var candidate := absf(degrees - float(variant.threshold))
		if candidate < distance:
			selected = variant
			distance = candidate
	return selected.tracks
