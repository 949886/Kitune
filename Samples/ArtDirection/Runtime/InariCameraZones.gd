extends "res://Samples/INARIMechanisms/Devices/CameraZone/CameraZoneController.gd"
## The original Cinemachine projection/framing renderer consumes the same
## region state as portable hosts. Cutscene/preview camera ownership stays here.
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Zone = preload("res://Samples/ArtDirection/Runtime/InariCameraZone.gd")
var stage: Node
var rig: Node
var marker := Node2D.new()
var owns_follow := false


func configure(owner_stage: Node, actor: Node, camera_rig: Node, is_loading: Callable) -> void:
	stage = owner_stage
	rig = camera_rig
	bind_actor(actor, func(): return actor.global_position + rig.player_origin_offset,
		is_loading, func(): return rig.freeze_remaining > 0.0)
	ignore_exit = func(body): return body.process_mode == Node.PROCESS_MODE_DISABLED and not body.dead
	pixels_per_unit = actor.units
	z_damping = float(rig.source.damping[2])
	tracked_offset = Vector3(rig.source.tracked_offset.x, rig.source.tracked_offset.y, rig.source.tracked_offset.z)
	var data: Dictionary = Assets.read_json(Assets.ROOT + "camera_zones.json")
	add_child(marker)
	soft_zone_changed.connect(func(unlimited):
		if _can_write_camera(): rig.framing.m_UnlimitedSoftZone = unlimited)
	for record: Dictionary in data.levels.get(stage.data.source, []):
		var zone := Zone.new()
		stage.add_child(zone)
		zone.configure(record.duplicate(true), self)


func _can_write_camera() -> bool:
	if rig.source.follow.has("fixed_position"):
		return false
	return not (is_instance_valid(stage.machinery.trial) and stage.machinery.trial.state == "preview")


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(player) or not _can_write_camera(): return
	# A timer may finish while a Timeline/route preview owns the rig. Reapply
	# current state when ownership returns so an old unlimited flag cannot stick.
	rig.framing.m_UnlimitedSoftZone = unlimited_soft_zone
	rig.source.damping[2] = z_damping
	if is_instance_valid(fixed_zone):
		marker.global_position = target_position
		rig.target = marker
		rig.target_offset = Vector2.ZERO
		rig.target_depth = target_depth
		owns_follow = true
	else:
		if owns_follow:
			rig.target = player
			owns_follow = false
		rig.target_offset = rig.player_origin_offset + Vector2(tracked_offset.x, -tracked_offset.y) * player.units
		rig.target_depth = tracked_offset.z
