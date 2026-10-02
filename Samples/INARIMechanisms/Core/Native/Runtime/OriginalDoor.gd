extends Node
## Original InteractiveDoor interaction flags and original fragment sprites.
## Source rigid-body coefficients and polygons, with Godot contact resolution.

const Assets = preload("OriginalAssets.gd")
const Debris = preload("OriginalDoorDebris.gd")
const Collision = preload("StudyCollision.gd")

signal impacted(interaction: int, destroyed: bool)
signal debris_cleared

var physics: Dictionary

var data: Dictionary
var pieces: Array[Dictionary] = []
var broken := false
var targetable := true
var enemy_damage := 0.0
var elapsed := 0.0
var audio: Node
var last_interaction_frame := -1
## Portable hosts bake their placement into world-space rigid bodies. The
## original stage retains its existing source-space rendering/projection path.
var use_host_space := false
var debris_layer := Collision.PARTICLE_SURFACE
var debris_mask := Collision.DOOR_DEBRIS_TARGET
var launch_random: RandomNumberGenerator


func _ready() -> void:
	if physics.is_empty():
		physics = Assets.read_json(Assets.ROOT + "door_physics.json")
	process_priority = 440
	set_process(false)


func receive_enemy_damage(amount: float, facing: float) -> void:
	if broken or data.get("invincible", false) or (int(data.interactions) & 4) == 0:
		return
	# Metal doors reject CommonAttack before health changes, but retain their
	# original impact response. The enemy's target lock does not block damage.
	if int(data.interactions) == 12:
		interact(4, facing)
		return
	enemy_damage += maxf(0.0, amount)
	if enemy_damage >= float(data.health):
		interact(4, facing)


func interact(kind: int, facing: float) -> bool:
	if broken or data.get("invincible", false) or (int(data.interactions) & kind) == 0:
		return false
	if last_interaction_frame == Engine.get_physics_frames():
		return false
	last_interaction_frame = Engine.get_physics_frames()

	# The original metal door reacts to light attacks but only breaks on heavy ones.
	if int(data.interactions) == 12 and kind == 4:
		audio.play("metal_door_hit")
		impacted.emit(kind, false)
		return true

	broken = true
	targetable = false
	audio.play("metal_door_break" if int(data.interactions) == 12 else "door_break")
	for piece: Dictionary in pieces:
		for body: Node2D in piece.bodies:
			body.set_deferred("collision_layer", 0)

		var degrees := (
			launch_random.randf_range(float(physics.angle_min), float(physics.angle_max))
			if launch_random != null
			else randf_range(float(physics.angle_min), float(physics.angle_max))
		)
		var angle := -deg_to_rad(degrees)
		piece.velocity = (
			Vector2(facing, 0.0).rotated(angle)
			* float(physics.launch_speed)
			* Debris.UNITS
			/ float(piece.mass)
		)
		piece.rigid = null
		# Creating physics bodies inside a hit/query callback must be deferred.
		_activate_piece.call_deferred(piece)
	set_process(true)
	impacted.emit(kind, true)
	return true


func _activate_piece(piece: Dictionary) -> void:
	var body := Debris.new()
	var initial_frame := Assets.matrix(piece.body_transform)
	var host: Node2D = get_parent()
	var launch: Vector2 = piece.velocity
	var collider_frame := Transform2D.IDENTITY
	if use_host_space:
		# Keep the rigid body unscaled; bake the complete placement basis into
		# its collision children. Moving the emptied host must not drag debris.
		body.top_level = true
		body.transform = Transform2D(0.0, (host.global_transform * initial_frame).origin)
		collider_frame = host.global_transform
		launch = host.global_transform.basis_xform(launch)
	else:
		body.transform = initial_frame
	body.configure(piece.rigid_body, physics, launch)
	body.collision_layer = debris_layer
	body.collision_mask = debris_mask
	for collider: Node2D in piece.bodies:
		for child: Node in collider.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				var copy: Node2D = child.duplicate()
				if copy is CollisionPolygon2D:
					# Stage polygons use edges to retain architectural holes. These
					# source fragments are single solid paths; moving bodies need
					# convex decomposition to collide with the static edge geometry.
					copy.build_mode = CollisionPolygon2D.BUILD_SOLIDS
				copy.transform = (
					body.transform.affine_inverse()
					* collider_frame
					* collider.transform
					* child.transform
				)
				body.add_child(copy)
	get_parent().add_child(body)
	piece.rigid = body
	piece.inverse_body = body.transform.affine_inverse()
	piece.visual_frames = []
	for visual: Node2D in piece.visuals:
		piece.visual_frames.append(visual.global_transform if use_host_space else visual.transform)


func _process(delta: float) -> void:
	elapsed += delta
	for piece: Dictionary in pieces:
		if not is_instance_valid(piece.rigid):
			continue
		var movement: Transform2D = piece.rigid.transform * piece.inverse_body
		for index in piece.visuals.size():
			var visual: Node2D = piece.visuals[index]
			# Keep the original projection parent and sorting. Apply rigid motion
			# in source XY coordinates before the camera projects the depth plane.
			if use_host_space:
				visual.global_transform = movement * piece.visual_frames[index]
			else:
				visual.transform = movement * piece.visual_frames[index]
			visual.modulate.a = maxf(0.0, 1.0 - elapsed / float(data.fade_time))

	if elapsed >= float(data.fade_time):
		for piece: Dictionary in pieces:
			if is_instance_valid(piece.rigid):
				piece.rigid.queue_free()
			piece.rigid = null
		set_process(false)
		debris_cleared.emit()
