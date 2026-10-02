extends RefCounted
## ShurikenObject's child trail and directly borrowed impact particles use global time.

const Afterimages = preload("res://Samples/ArtDirection/Runtime/InariKunaiAfterimages.gd")


static func start_flight(stage: Node, visual: Node2D) -> Node2D:
	if not is_instance_valid(stage):
		return null
	var effect: Node2D = stage.spawn_effect(
		"KunaiFlight", visual.global_position, visual.global_rotation, false, visual, false
	)
	effect.follow_rotation = true
	var afterimages := Afterimages.new()
	effect.add_child(afterimages)
	afterimages.configure(effect, stage)
	return effect


static func stop_flight(effect: Node2D) -> void:
	if is_instance_valid(effect):
		for child: Node in effect.get_children():
			if child is Afterimages:
				child.clear()
		# Native SetActive(false) removes existing particles on the collision frame.
		effect.hide()
		effect.process_mode = Node.PROCESS_MODE_DISABLED
		effect.queue_free()


static func stick(stage: Node, visual: Node2D) -> void:
	if is_instance_valid(stage):
		stage.spawn_effect(
			"Eff_Player_KunaiStick",
			visual.global_position,
			visual.global_rotation,
			false,
			null,
			false
		)


static func bounce(stage: Node, visual: Node2D) -> void:
	if is_instance_valid(stage):
		# BounceDestroy changes position only; the exported prefab retains its rotation.
		stage.spawn_effect(
			"Eff_Player_KunaiDestroy", visual.global_position, 0.0, false, null, false
		)
