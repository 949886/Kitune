extends SceneTree
## Original pixel hashes, burst schedule, lifetime curves, flipbook and simulation spaces.

const Effect = preload("res://Samples/ArtDirection/Runtime/OriginalParticleEffect.gd")
const Values = preload("res://Samples/ArtDirection/Runtime/UnityParticleValues.gd")


func _initialize() -> void:
	call_deferred("run")


func make_effect(stage: Node, key: String, point: Vector2) -> Node2D:
	var result := Effect.new()
	stage.add_child(result)
	result.position = point
	result.configure(key, stage.sort_depth, null, 12345)
	result.set_process(false)
	for emitter: Node in result.emitters:
		emitter.set_process(false)
	return result


func advance(effect: Node, duration: float) -> void:
	for frame in roundi(duration * 60.0):
		for emitter: Node in effect.emitters:
			emitter.advance(1.0 / 60.0)


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	for enemy: Node in lab.stage.enemies:
		enemy.ranged_combat.target = null
	var shot := make_effect(lab.stage, "Eff_RifleMan_Shot", lab.player.position)
	var hit := make_effect(
		lab.stage, "Eff_Enemy_Bullet_Ground", lab.player.position + Vector2(100, 0)
	)
	assert(shot.emitters.size() == 3 and hit.emitters.size() == 2)
	for effect: Node in [shot, hit]:
		for emitter: Node in effect.emitters:
			var pixels: Image = emitter.texture.get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(pixels.get_data())
			assert(hash.finish().hex_encode() == emitter.data.texture.pixel_sha256)
	advance(shot, 0.05)
	advance(hit, 0.05)
	var spark: Node = shot.emitters[0]
	var smoke: Node = shot.emitters[1]
	var fire: Node = shot.emitters[2]
	assert(spark.emitted == 10 and smoke.emitted == 10 and fire.emitted == 1)
	assert(hit.emitters[0].emitted == 20 and hit.emitters[1].emitted == 3)
	assert(fire.particles.size() == 1 and fire.particles[0].visual.hframes == 3)
	assert(fire.particles[0].visual.vframes == 3)
	assert(fire.particles[0].visual.frame > 0, "Flame must advance through original texture cells")

	# Source spark/smoke use World simulation; the fire uses Local simulation.
	var spark_position: Vector2 = spark.particles[0].visual.global_position
	var fire_position: Vector2 = fire.particles[0].visual.global_position
	shot.position.x += 80.0
	spark._update(spark.particles[0], 0.0)
	fire._update(fire.particles[0], 0.0)
	assert(spark.particles[0].visual.global_position.is_equal_approx(spark_position))
	assert(fire.particles[0].visual.global_position.is_equal_approx(fire_position + Vector2(80, 0)))
	shot.scale.x = -1.0
	fire._update(fire.particles[0], 0.0)
	assert(fire.particles[0].visual.flip_h)
	assert(
		absf(fire.particles[0].visual.rotation) < 0.001,
		"Horizontal mirror must not add a vertical flip"
	)

	advance(shot, 0.30)
	assert(smoke.emitted == 13, "Source smoke emits three more particles after 0.3 seconds")
	assert(fire.emitted == 1 and fire.particles.is_empty())
	advance(shot, 2.1)
	advance(hit, 2.5)
	for effect: Node in [shot, hit]:
		assert(effect.emitters.all(func(emitter: Node): return emitter.particles.is_empty()))
		effect.set_process(true)
	await process_frame
	await process_frame
	assert(not is_instance_valid(shot) and not is_instance_valid(hit))
	lab.queue_free()
	await process_frame
	print("PARTICLE_PROBE_PASS")
	quit()
