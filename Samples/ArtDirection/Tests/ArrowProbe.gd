extends SceneTree
## Real rigid-body arrow flight, continuous wall contact, source masks and player damage.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")
const SourceCurve = preload("res://Samples/ArtDirection/Runtime/UnityCurve.gd")

var lab: Node
var bow: Node
var impacts: Array[Dictionary] = []
var source: Dictionary


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func shoot(point: Vector2, angle := 0.0, damage := 1) -> RigidBody2D:
	return lab.stage.spawn_arrow(point, angle, float(bow.data.profile.ProjectileSpeed), bow, damage)


func obstacle(point: Vector2, mask: int, size := Vector2(1, 100)) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = mask
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	lab.stage.add_child(body)
	body.position = point
	return body


func wait_hit(arrow: Node) -> void:
	for index in 60:
		if not is_instance_valid(arrow):
			return
		await frames(1)
	assert(false, "Original arrow failed to contact the target")


func run() -> void:
	lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	lab.story_mode = true
	root.add_child(lab)
	lab.load_level(0)
	lab.player.set_physics_process(false)
	for enemy: Node in lab.stage.enemies:
		enemy.set_physics_process(false)
		if int(enemy.data.go) == 3454:
			bow = enemy
	assert(bow != null and bow.data.profile.ProjectileSpeed == 85.0)
	lab.stage.effect_started.connect(
		func(effect: Node2D):
			if effect.effect_key == "Eff_ArrowDestroy":
				impacts.append({"point": effect.global_position, "angle": effect.global_rotation})
	)
	var location := Vector2(-20000, -20000)
	var arrow := shoot(location, -0.3)
	source = arrow.source
	assert(source.damage == 1.0 and source.destroy_effect == "Eff_ArrowDestroy")
	assert("Door" not in source.collision_layers and "Platform" not in source.collision_layers)
	assert("Enemy" not in source.collision_layers and "Player" in source.collision_layers)
	assert(arrow.mass == 1.0 and arrow.gravity_scale == 0.0 and arrow.linear_damp == 0.0)
	assert(source.rigidbody.m_CollisionDetection == 1)
	assert(arrow.continuous_cd == RigidBody2D.CCD_MODE_DISABLED)
	assert(is_equal_approx(arrow.collision_shape.shape.radius, 0.8))
	assert(arrow.collision_shape.position.is_equal_approx(Vector2(-7.2, -1.04)))
	assert(arrow.flight_effect.follow_actor == arrow and arrow.flight_effect.follow_rotation)
	for entry in [
		[arrow.visual.texture, source.visual.sprite], [arrow.trail.texture, source.trail.texture]
	]:
		var pixels: Image = entry[0].get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(pixels.get_data())
		assert(hash.finish().hex_encode() == entry[1].pixel_sha256)
	await frames(2)
	var velocity := Vector2.from_angle(-0.3) * 1360.0
	assert(arrow.linear_velocity.is_equal_approx(velocity))
	var start := arrow.global_position
	await frames(10)
	assert(arrow.global_position.distance_to(start + velocity * (10.0 / 60.0)) < 0.1)
	assert(is_equal_approx(arrow.rotation, -0.3), "Source rotation lock must survive flight")
	assert(arrow.trail.points.size() > 2)
	assert(arrow.flight_effect.emitters[0].emitted > 0)
	assert(arrow.trail.width == 8.0)
	var curve: Dictionary = source.trail.renderer.m_Parameters.widthCurve
	assert(absf(arrow.trail.width_curve.sample(0.5) - SourceCurve.evaluate(curve, 0.5)) < 0.001)
	arrow.freeze = true
	await frames(2)
	await frames(15)
	assert(arrow.trail.points.size() == 1 and arrow.trail.samples.is_empty())
	var flight: Node = arrow.flight_effect
	arrow.queue_free()
	await frames(2)
	assert(not is_instance_valid(flight), "Removing an arrow must also release its looping effects")

	# The tiny source circle must hit a wall thinner than one physics-step movement.
	var wall := obstacle(location + Vector2(101, 0), Collision.ARROW_SURFACE)
	await frames(2)
	arrow = shoot(location)
	await wait_hit(arrow)
	assert(impacts.size() == 1)
	assert(absf(impacts[0].point.x - (wall.position.x - 0.5 - 0.8)) < 1.0)
	assert(absf(impacts[0].point.y - (location.y - 1.04)) < 0.02)
	assert(impacts[0].angle == 0.0, "Arrow hit effects use identity rotation")
	wall.queue_free()
	await frames(2)

	# These Godot fixtures carry the existing door/platform/enemy masks, with no arrow bit.
	var excluded: Array[Node] = []
	for mask in [Collision.SOLID | Collision.DAMAGEABLE, Collision.ONE_WAY, Collision.DAMAGEABLE]:
		excluded.append(obstacle(location + Vector2(50 + excluded.size() * 40, 0), mask))
	await frames(2)
	arrow = shoot(location)
	await frames(12)
	assert(is_instance_valid(arrow) and impacts.size() == 1 and arrow.position.x > location.x + 200)
	arrow.queue_free()
	for body in excluded:
		body.queue_free()
	await frames(2)

	# The real study player receives one HP even when Shoot stores a much larger value.
	lab.player.position = location + Vector2(130, 0) - lab.player.body_shape.position
	lab.player.action_state = ""
	await frames(2)
	var health := float(lab.player.damage.health)
	arrow = shoot(location, 0.0, 99)
	assert(arrow.launch_damage == 99)
	await wait_hit(arrow)
	assert(lab.player.damage.health == health - 1.0 and impacts.size() == 2)
	arrow = shoot(location)
	await wait_hit(arrow)
	assert(lab.player.damage.health == health - 1.0 and impacts.size() == 3)
	assert(
		lab.player.damage.blinking,
		"Invulnerability rejects HP loss while still consuming the arrow"
	)
	# A grazing hit must use the original circle radius, not a zero-width center ray.
	wall = obstacle(location + Vector2(101, -0.34), Collision.ARROW_SURFACE, Vector2(1, 0.2))
	await frames(2)
	arrow = shoot(location)
	await wait_hit(arrow)
	assert(impacts.size() == 4 and absf(impacts[-1].point.x - wall.position.x) < 2.0)
	wall.queue_free()

	# Verify the actual imported collider assignment rather than only the fixture masks.
	var checked := 0
	for child: Node in lab.stage.get_children():
		if child is StaticBody2D and child.has_meta("source_layer"):
			var expected: bool = child.get_meta("source_layer") in source.collision_layers
			assert(bool(child.collision_layer & Collision.ARROW_SURFACE) == expected)
			checked += 1
	assert(checked > 20)
	if DisplayServer.get_name() != "headless":
		await screenshot()
	lab.queue_free()
	await frames(2)
	print("ARROW_PROBE_PASS impacts=", impacts.size(), " colliders=", checked)
	quit()


func screenshot() -> void:
	lab.player.respawn()
	lab.player.set_physics_process(false)
	await frames(2)
	# Find a real clear segment around the camera; the rotating gear is a solid collider.
	var launch := Vector2.INF
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = float(source.collider.m_Radius) * 16.0
	query.collision_mask = Collision.ARROW_SURFACE | Collision.PLAYER
	query.motion = Vector2(180, 0)
	var space: PhysicsDirectSpaceState2D = lab.stage.get_world_2d().direct_space_state
	for y in range(-140, -10, 20):
		for x in range(-100, 100, 40):
			var candidate: Vector2 = lab.player.position + Vector2(x, y)
			query.transform = Transform2D(0.0, candidate + Vector2(-7.2, -1.04))
			query.motion = Vector2.ZERO
			var overlapping := not space.intersect_shape(query, 1).is_empty()
			query.motion = Vector2(180, 0)
			if not overlapping and space.cast_motion(query)[0] == 1.0:
				launch = candidate
				break
		if launch != Vector2.INF:
			break
	assert(launch != Vector2.INF, "GPU fixture needs a clear flight segment in the original scene")
	var arrow := shoot(launch)
	await frames(7)
	assert(is_instance_valid(arrow), "GPU fixture must show a flying arrow")
	arrow.freeze = true
	arrow.trail.set_process(false)
	arrow.flight_effect.set_process(false)
	for emitter: Node in arrow.flight_effect.emitters:
		emitter.set_process(false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/art-direction/inari_arrow_flight.png")
