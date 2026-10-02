extends SceneTree
## Reproduce the real body_entered -> complete_step -> open_gate signal chain.
## The collision must disappear after query flushing, and repeated completion
## must preserve the normal opening animation and eventual gate removal.


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	# Load after SceneTree initialization so the player's Chronos autoload is
	# registered before compiling the controller's typed player dependency.
	var controller: Node = load("res://Game/Tutorial/TutorialProgressController.gd").new()
	controller.name = "Controller"
	fixture.add_child(controller)
	var gate: StaticBody2D = load("res://Game/Tutorial/TutorialGate.gd").new()
	gate.name = "Gate"
	gate.controller_path = NodePath("../Controller")
	gate.open_on_step_id = "move"
	gate.position = Vector2(40, 0)
	fixture.add_child(gate)
	var shape: CollisionShape2D = gate.get_node("CollisionShape2D")
	var trigger: Area2D = load("res://Game/Tutorial/TutorialEventTrigger.gd").new()
	trigger.controller_path = NodePath("../Controller")
	trigger.step_id = "move"
	trigger.gate_to_remove_path = NodePath("../Gate")
	trigger.collision_mask = 2
	var trigger_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(80, 80)
	trigger_shape.shape = rectangle
	trigger.add_child(trigger_shape)
	fixture.add_child(trigger)
	var actor := CharacterBody2D.new()
	actor.collision_layer = 2
	actor.collision_mask = 0
	actor.position = Vector2(-100, 0)
	actor.add_to_group("Player")
	var actor_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5
	actor_shape.shape = circle
	actor.add_child(actor_shape)
	fixture.add_child(actor)
	await frames(3)
	assert(not shape.disabled and not controller.is_step_completed("move"))
	# A mismatched step must leave this gate closed.
	controller.complete_step("jump")
	assert(not shape.disabled)
	actor.position = Vector2.ZERO
	await frames(3)
	assert(controller.is_step_completed("move") and trigger.has_overlapping_bodies())
	assert(shape.disabled, "The gate collider must be disabled after flushing")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = gate.global_position
	query.collision_mask = 1
	assert(fixture.get_world_2d().direct_space_state.intersect_point(query).is_empty())
	controller.complete_step("move")
	gate.open_gate()
	var observed: WeakRef = weakref(gate)
	await frames(20)
	assert(observed.get_ref() == null, "The opening tween must still remove the gate")
	fixture.queue_free()
	await process_frame
	print("TUTORIAL_GATE_PASS")
	quit()
