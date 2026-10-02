extends Node2D
## Original bursts, texture-sheet animation and 3D particle values projected into 2D.
## NoiseModule remains unported; collision and velocity damping use Godot approximations.

const Values = preload("UnityParticleValues.gd")
const MaterialSettings = preload("OriginalMaterial.gd")
const Glow = preload("../Shaders/OriginalGlow.gdshader")
const Unlit = preload("../Shaders/OriginalUnlitParticle.gdshader")
const Collision = preload("StudyCollision.gd")
const Shockwave = preload("../Shaders/OriginalShockwave.gdshader")
static var ROOT: String = (preload("../../../PackageLocation.gd") as Script).resource_path.get_base_dir() + "/Assets/Particles/"
const UNITS := 16.0

var data: Dictionary
var system: Dictionary
var particles: Array[Dictionary] = []
var random := RandomNumberGenerator.new()
var clock := 0.0
var delay := 0.0
var emitted := 0
var next_rate := 0.0
var bursts: Dictionary = {}
var pose: Transform3D
var gravity: Vector3
var texture: Texture2D
var shared_material: ShaderMaterial
var effect: Node2D
var emission_cycle := -1
var distance_remainder := 0.0
var distance_factor := 0.0
var previous_origin := Vector3.ZERO
var time_scale_override := -1.0
var is_shockwave := false
var start_color_override: Variant = null
## Standalone hosts map the source surface mask to their own physics layers.
var collision_mask := Collision.PARTICLE_SURFACE
## Optional relocated hierarchy frame (for particles on moving fragments).
## Existing effects continue to use their owning effect's global transform.
var frame_transform: Callable


func configure(
	source: Dictionary, owner_effect: Node2D, source_gravity: Dictionary, seed_value: int
) -> void:
	configure_source(
		source, owner_effect, source_gravity, seed_value, ROOT, owner_effect.get_parent().lighting
	)


## Standalone devices supply their own resource root and optional lighting.
## The particle simulation does not require a stage or a particular player.
func configure_source(
	source: Dictionary,
	owner_effect: Node2D,
	source_gravity: Dictionary,
	seed_value: int,
	texture_root: String,
	lighting_provider: Node = null
) -> void:
	data = source
	system = data.system
	effect = owner_effect
	pose = Values.transform(data.transform)
	gravity = Vector3(source_gravity.x, source_gravity.y, 0)
	random.seed = seed_value
	delay = Values.number(system.startDelay, 0, random.randf())
	texture = load(texture_root + data.texture.path)
	shared_material = ShaderMaterial.new()
	is_shockwave = data.material.shader == "Shader Graphs/ShockWave"
	if is_shockwave:
		assert(data.renderer.m_UseCustomVertexStreams)
		assert(data.renderer.m_VertexStreams.any(func(value): return int(value) == 21))
		shared_material.shader = Shockwave
		shared_material.set_shader_parameter(
			"distortion_strength", data.material.floats._DistortionStrength
		)
		shared_material.set_shader_parameter("ring_size", data.material.floats._Size)
	elif data.material.shader == "Universal Render Pipeline/Particles/Unlit":
		_configure_unlit()
	else:
		shared_material.shader = Glow
		MaterialSettings.configure(shared_material, data.material, get_viewport().use_hdr_2d)
	material = shared_material
	if lighting_provider != null:
		lighting_provider.apply_source(
			self,
			data.material,
			int(data.renderer.m_SortingLayerID),
			"particle:" + str(data.material.name)
		)
	shared_material = material as ShaderMaterial
	previous_origin = _world_pose().origin
	if float(system.EmissionModule.rateOverDistance.scalar) > 0.0:
		# Native particle RNG is unavailable; keep one rate sample per emitter.
		distance_factor = random.randf()
	process_priority = 430


func _configure_unlit() -> void:
	var source: Dictionary = data.material
	assert(source.floats._SrcBlend == 5 and source.floats._DstBlend == 10)
	shared_material.shader = Unlit
	shared_material.set_shader_parameter("linear_framebuffer", get_viewport().use_hdr_2d)
	shared_material.set_shader_parameter(
		"material_tint",
		Values.rgba(
			{"r": source.color[0], "g": source.color[1], "b": source.color[2], "a": source.color[3]}
		)
	)
	var mode := 0
	if "_COLORCOLOR_ON" in source.keywords:
		mode = 1
	elif "_COLORADDSUBDIFF_ON" in source.keywords:
		mode = 2
	shared_material.set_shader_parameter("color_mode", mode)
	var operation: Array = source.particle_color_operation
	shared_material.set_shader_parameter("color_operation", Vector2(operation[0], operation[1]))


func _process(delta: float) -> void:
	advance(delta)


## Opt-in source prewarm for continuously running scene devices. Unity warms
## one loop in simulation time, independently of the later playback multiplier.
## Substeps populate ages/positions instead of emitting one pile at the nozzle.
## Existing one-shot effects do not call this method and retain their lifecycle.
func prewarm_source() -> void:
	if clock > 0.0 or not system.prewarm or not system.looping:
		return
	if not system.EmissionModule.enabled:
		return
	var previous_speed := time_scale_override
	time_scale_override = 1.0
	var duration := float(system.lengthInSec)
	var steps := ceili(duration * 60.0)
	for index in steps:
		advance(duration / float(steps))
	time_scale_override = previous_speed


func advance(delta: float) -> void:
	var speed: float = system.simulationSpeed if time_scale_override < 0.0 else time_scale_override
	var step := delta * speed
	if step <= 0.0:
		return
	var previous_time := clock - delay
	clock += step
	var emission: Dictionary = system.EmissionModule
	var time := clock - delay
	if emission.enabled and time >= 0.0:
		_emit_time(previous_time, time)
		if system.looping or time < float(system.lengthInSec):
			_emit_distance(time)
	elif time >= 0.0:
		# Emission disabled is not a paused simulation. Skip births in this
		# interval so a reusable device cannot accumulate a burst while off.
		var duration := float(system.lengthInSec)
		var cycle := floori(time / duration) if system.looping else 0
		if emission_cycle != cycle:
			emission_cycle = cycle
			bursts.clear()
		next_rate = fposmod(time, duration) if system.looping else time
		for index in emission.m_Bursts.size():
			if float(emission.m_Bursts[index].time) <= next_rate:
				bursts[index] = true
		distance_remainder = 0.0
	previous_origin = _world_pose().origin
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle.age += step
		if particle.age >= particle.life:
			particle.visual.queue_free()
			particles.remove_at(index)
			continue
		_update(particle, step)
	if not system.looping and time > float(system.lengthInSec) and particles.is_empty():
		set_process(false)


func _emit_time(previous_time: float, time: float) -> void:
	var duration := float(system.lengthInSec)
	var first := floori(maxf(0.0, previous_time) / duration) if system.looping else 0
	var last := floori(time / duration) if system.looping else 0
	var emission: Dictionary = system.EmissionModule
	for cycle in range(first, last + 1):
		if cycle != emission_cycle:
			emission_cycle = cycle
			bursts.clear()
			next_rate = 0.0
		var local_time := minf(time - cycle * duration, duration)
		for index in emission.m_Bursts.size():
			var burst: Dictionary = emission.m_Bursts[index]
			if not bursts.has(index) and local_time >= float(burst.time):
				bursts[index] = true
				if random.randf() <= float(burst.probability):
					for count in roundi(
						Values.number(burst.countCurve, local_time, random.randf())
					):
						_spawn()
		var rate := Values.number(emission.rateOverTime, local_time / duration, random.randf())
		if rate > 0.0:
			while (
				next_rate <= local_time
				and next_rate < duration
				and not is_equal_approx(next_rate, duration)
			):
				_spawn()
				next_rate += 1.0 / rate


func _emit_distance(time: float) -> void:
	var frame := _world_pose()
	var distance := previous_origin.distance_to(frame.origin)
	var phase := fmod(time, float(system.lengthInSec)) / float(system.lengthInSec)
	var rate := Values.number(system.EmissionModule.rateOverDistance, phase, distance_factor)
	var amount := distance * rate
	if amount <= 0.0:
		return
	var accumulated := distance_remainder + amount
	for index in floori(accumulated):
		# Distribute births along the traveled segment instead of clumping at its end.
		var weight := (float(index + 1) - distance_remainder) / amount
		var birth_pose := frame
		birth_pose.origin = previous_origin.lerp(frame.origin, weight)
		_spawn(birth_pose)
	distance_remainder = fmod(accumulated, 1.0)


func _spawn(spawn_pose: Variant = null) -> void:
	var initial: Dictionary = system.InitialModule
	if particles.size() >= int(initial.maxNumParticles):
		return
	var factor := random.randf()
	var sampled := _shape()
	var space: Transform3D = _world_pose() if spawn_pose == null else spawn_pose
	var local := int(system.moveWithTransform) == 0
	var position: Vector3 = sampled.position if local else space * sampled.position
	var velocity: Vector3 = sampled.direction * Values.number(initial.startSpeed, 0, factor)
	if not local:
		velocity = space.basis * velocity
	var visual := Sprite2D.new()
	visual.texture = texture
	visual.material = shared_material
	if is_shockwave:
		# AgePercent belongs to an individual particle, not the pooled emitter.
		visual.material = shared_material.duplicate()
	visual.top_level = true
	visual.z_as_relative = false
	visual.z_index = effect.sorting.call(
		[data.renderer.m_SortingLayer, data.renderer.m_SortingOrder]
	)
	visual.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if int(data.texture.filter) == 0
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	if system.UVModule.enabled:
		visual.hframes = int(system.UVModule.tilesX)
		visual.vframes = int(system.UVModule.tilesY)
	add_child(visual)
	var particle := {
		"age": 0.0,
		"life": Values.number(initial.startLifetime, 0, factor),
		"factor": factor,
		"position": position,
		"velocity": velocity,
		"local": local,
		"size": Values.number(initial.startSize, 0, factor),
		"rotation": Values.number(initial.startRotation, 0, factor),
		"color": Values.color(initial.startColor, 0, random.randf()),
		"visual": visual,
		"initial_pose": space
	}
	particles.append(particle)
	# Changing Unity main.startColor affects births only, preserving existing particle colors.
	if start_color_override != null:
		particle.color = start_color_override
	emitted += 1
	_update(particle, 0.0)


func _shape() -> Dictionary:
	var shape: Dictionary = system.ShapeModule
	if not shape.enabled:
		return {"position": Vector3.ZERO, "direction": Vector3(0, 0, 1)}
	var azimuth := random.randf() * deg_to_rad(float(shape.arc.value))
	var radial := Vector3(cos(azimuth), sin(azimuth), 0)
	var radius := float(shape.radius.value)
	var position: Vector3
	var direction: Vector3
	if int(shape.type) == 0:
		var z := random.randf_range(-1.0, 1.0)
		direction = Vector3(radial.x * sqrt(1.0 - z * z), radial.y * sqrt(1.0 - z * z), z)
		position = direction * radius * pow(random.randf(), 1.0 / 3.0)
	elif int(shape.type) == 10:
		# Circle emission lies in local XY and points radially outward. The
		# source explosion uses zero thickness, placing dust on the perimeter.
		var radius_factor := sqrt(
			lerpf(pow(1.0 - float(shape.radiusThickness), 2), 1.0, random.randf())
		)
		position = radial * radius * radius_factor
		direction = radial
	else:
		assert(int(shape.type) == 4, "Unsupported source particle shape")
		var radius_factor := sqrt(
			lerpf(pow(1.0 - float(shape.radiusThickness), 2), 1.0, random.randf())
		)
		position = radial * radius * radius_factor
		var cone_angle := deg_to_rad(float(shape.angle)) * radius_factor
		direction = radial * sin(cone_angle) + Vector3(0, 0, cos(cone_angle))
	var rotation := Values.vector(shape.m_Rotation) * PI / 180.0
	# Unity Transform Euler order is Z, X, Y; retain the original 3D cone axis.
	var basis := Basis.from_euler(rotation, EULER_ORDER_YXZ)
	return {
		"position":
		basis * (position * Values.vector(shape.m_Scale)) + Values.vector(shape.m_Position),
		"direction": basis * direction
	}


func _world_pose() -> Transform3D:
	var frame: Transform2D = (
		frame_transform.call() if frame_transform.is_valid() else effect.global_transform
	)
	var root := Transform3D(
		Basis(
			Vector3(frame.x.x, -frame.x.y, 0), Vector3(-frame.y.x, frame.y.y, 0), Vector3(0, 0, 1)
		),
		Vector3(frame.origin.x / UNITS, -frame.origin.y / UNITS, 0)
	)
	return root * pose


func _update(particle: Dictionary, delta: float) -> void:
	var age := float(particle.age) / float(particle.life)
	var factor := float(particle.factor)
	var frame := _world_pose()
	var gravity_vector := gravity * Values.number(system.InitialModule.gravityModifier, age, factor)
	# Some native flat effects have a zero Z scale and no gravity. Avoid
	# inverting their singular transform for an already-zero acceleration.
	if particle.local and gravity_vector != Vector3.ZERO:
		gravity_vector = frame.basis.inverse() * gravity_vector
	particle.velocity += gravity_vector * delta
	var velocity: Vector3 = particle.velocity
	var module: Dictionary = system.VelocityModule
	if module.enabled:
		var extra := Vector3(
			Values.number(module.x, age, factor),
			Values.number(module.y, age, factor),
			Values.number(module.z, age, factor)
		)
		if particle.local and module.inWorldSpace:
			extra = frame.basis.inverse() * extra
		elif not particle.local and not module.inWorldSpace:
			extra = frame.basis * extra
		velocity += extra
	module = system.ClampVelocityModule
	if module.enabled:
		var before_clamp := velocity
		var limit := Values.number(module.magnitude, age, factor)
		if velocity.length() > limit:
			# Godot-side damping approximation; Unity's native integrator is not available.
			velocity = velocity.normalized() * lerpf(velocity.length(), limit, float(module.dampen))
		particle.velocity += velocity - before_clamp
	var previous: Vector3 = particle.position
	particle.position += velocity * delta
	_collide(particle, previous, frame)
	var world: Vector3 = frame * particle.position if particle.local else particle.position
	var visual: Sprite2D = particle.visual
	if is_shockwave:
		visual.material.set_shader_parameter("age_percent", age)
	visual.global_position = Vector2(world.x, -world.y) * UNITS
	var size := Vector2.ONE * float(particle.size)
	module = system.SizeModule
	if module.enabled:
		size.x *= Values.number(module.curve, age, factor)
		size.y *= Values.number(module.y if module.separateAxes else module.curve, age, factor)
	var scale_3d := frame.basis.get_scale()
	visual.scale = (
		size
		* Vector2(scale_3d.x, scale_3d.y)
		* UNITS
		/ Vector2(texture.get_width() / visual.hframes, texture.get_height() / visual.vframes)
	)
	module = system.RotationBySpeedModule
	if system.RotationModule.enabled:
		particle.rotation += Values.number(system.RotationModule.curve, age, factor) * delta
	if module.enabled:
		particle.rotation += Values.number(module.curve, velocity.length(), factor) * delta
	var mirrored := frame.basis.determinant() < 0.0
	var right := frame.basis.x * (-1.0 if mirrored else 1.0)
	var alignment := -atan2(right.y, right.x) if int(data.renderer.m_RenderAlignment) == 2 else 0.0
	visual.rotation = alignment - float(particle.rotation)
	visual.flip_h = mirrored
	visual.modulate = particle.color
	if system.ColorModule.enabled:
		visual.modulate *= Values.color(system.ColorModule.gradient, age, factor)
	module = system.UVModule
	if module.enabled:
		var fraction := Values.number(module.frameOverTime, age, factor) * float(module.cycles)
		visual.frame = clampi(
			floori(fraction * visual.hframes * visual.vframes),
			0,
			visual.hframes * visual.vframes - 1
		)


func _collide(particle: Dictionary, previous: Vector3, frame: Transform3D) -> void:
	var module: Dictionary = system.CollisionModule
	if not module.enabled:
		return
	var start: Vector3 = frame * previous if particle.local else previous
	var end: Vector3 = frame * particle.position if particle.local else particle.position
	var from := Vector2(start.x, -start.y) * UNITS
	var to := Vector2(end.x, -end.y) * UNITS
	if from.is_equal_approx(to):
		return
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(from, to, collision_mask)
	)
	if hit.is_empty():
		return
	var normal := Vector3(hit.normal.x, -hit.normal.y, 0)
	if particle.local:
		normal = (frame.basis.inverse() * normal).normalized()
	particle.velocity = particle.velocity.bounce(normal) * Values.number(module.m_Bounce)
	particle.position = previous
