extends SceneTree
## Exercise live player attacks against source enemy collision and health data.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var lab = load("res://Samples/ArtDirection/ArtDirectionLab.tscn").instantiate()
	root.add_child(lab)
	lab.load_level(0)
	assert(lab.stage.enemies.size() == 6)
	var bow: Node
	var rifle: Node
	for enemy: Node in lab.stage.enemies:
		# Damage timing is isolated from locomotion; PatrolProbe covers active AI.
		enemy.patrol.enabled = false
		if enemy.data.kind == "EnemyBowMan":
			bow = enemy
		elif enemy.data.kind == "EnemyRifleMan":
			rifle = enemy
	assert(bow != null and rifle != null)
	assert(bow.health == 280.0 and rifle.health == 100.0)
	for frame in 12:
		await physics_frame

	# Put the player on the same source platform, facing the original bow enemy.
	lab.player.position = bow.position + Vector2(-50.0, 32.0)
	lab.player.velocity = Vector2.ZERO
	lab.player.facing = 1.0
	lab.player.stamina = 0.0
	for frame in 3:
		await physics_frame
	var start: Vector2 = bow.position
	var impulses: Array[String] = []
	lab.player.camera_shake_requested.connect(func(kind: String): impulses.append(kind))
	var attack: StringName = lab.player.input_action("attack")
	Input.action_press(attack)
	await physics_frame
	Input.action_release(attack)
	for frame in 15:
		await physics_frame
	assert(bow.health == 240.0, "One real attack must deal the source 40 damage exactly once")
	assert(impulses == ["Attack"], "A real melee hit must generate exactly one source impulse")
	assert(bow.position.x > start.x + 20.0, "Source knockback was not applied")
	assert(lab.player.stamina >= 5.0, "Successful hit must return the source attack stamina")
	var material: ShaderMaterial = bow.visuals[bow.data.primary_visual].material
	assert(material.get_shader_parameter("hit_blend") == 0.0, "Hit flash did not expire")

	# Completing an incoming movement must not erase a shared attack profile.
	bow.ranged_combat.target = null
	var movement := {
		"Curve": rifle.data.profile.AttackInfoList[0].AttackMovementInfo.Curve,
		"Power": 0.1,
		"Duration": 2.0 / 60.0,
	}
	var saved_movement := movement.duplicate(true)
	bow.receive_study_hit({"Damage": 0.0, "AttackKnockBackInfo": movement}, 1.0)
	assert(not bow.knockback.is_empty())
	for frame in 4:
		await physics_frame
	assert(bow.knockback.is_empty() and movement == saved_movement)

	# Instance-local feedback must not flash unrelated enemies sharing a material.
	bow.receive_study_hit({"Damage": 1.0}, 1.0)
	assert(is_equal_approx(material.get_shader_parameter("hit_blend"), 0.8))
	var other_material: ShaderMaterial = rifle.visuals[rifle.data.primary_visual].material
	assert(other_material.get_shader_parameter("hit_blend") == 0.0)

	var death_count := [0]
	bow.defeated.connect(func(): death_count[0] += 1)
	bow.receive_study_hit({"Damage": 1000.0, "source_actor": lab.player}, 1.0)
	bow.receive_study_hit({"Damage": 1000.0, "source_actor": lab.player}, 1.0)
	assert(bow.dead and bow.health == 0.0 and death_count[0] == 1)
	for visual: Node2D in bow.visuals.values():
		assert(not visual.visible)

	rifle.receive_study_hit({"Damage": 100.0}, -1.0)
	assert(rifle.dead and rifle.death_animation.tracks.size() == 1)
	var death_track: Dictionary = rifle.death_animation.tracks[0]
	assert("Dead" in death_track.clip.clip)
	var first_sprite = death_track.node.current_sprite
	rifle.death_animation.advance(0.25)
	rifle.death_animation.advance(0.25)
	assert(death_track.node.current_sprite != first_sprite, "Death animation did not advance")
	rifle._update_corpse(float(rifle.data.profile.DisappearDelayTime) + 2.0)
	for visual: Node2D in rifle.visuals.values():
		assert(not visual.visible)

	lab.load_level(1)
	assert(lab.stage.enemies.is_empty(), "Cutscene actors must not become combat enemies")
	print("ENEMY_PROBE_PASS")
	lab.queue_free()
	await process_frame
	quit()
