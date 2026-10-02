@tool
extends "../../Core/DeviceHost.gd"
## Cabin, button, gates and the source mid-route exit, without a global scene
## manager or player. Host input calls interact(actor); scene changes are signals.
signal interaction_available(actor: Node, available: bool)
signal projectile_recall_requested(actor: Node)
signal doors_changed(closed: bool)
signal started
signal arrived
signal passenger_crushed(actor: CharacterBody2D)
signal scene_exit_requested(actor: Node, destination: String)
const Platform = preload("../../Core/Native/Runtime/InariMovingPlatform.gd")
const NativeButton = preload("../../Core/Native/Runtime/InariElevator.gd")
const Portal = preload("../../Core/Native/Runtime/InariScenePortal.gd")
const Assets = preload("../../Core/Native/Runtime/OriginalAssets.gd")
const Emitter = preload("../../Core/DeviceEmitter.gd")
const Configuration = preload("ElevatorSettings.gd")
@export var settings: Configuration = preload("ElevatorSettings.tres")
@export_flags_2d_physics var solid_layers := 1
@export_flags_2d_physics var actor_layers := 4
@export_flags_2d_physics var particle_collision_mask := 1
@export var scene_exit_enabled := true
@export var random_seed := 17
var platform: StaticBody2D
var mechanism: Area2D
var portal: Area2D
var child_bodies: Array[StaticBody2D] = []
var ambient_emitters: Array[Node] = []
var actor_ref: WeakRef
var eligible: Callable
var available := false
var outline_tween: Tween
var sorting: Callable = func(order: Array): return int(order[1])


func _ready() -> void:
	var record := prepare("Elevator")
	if Engine.is_editor_hint():
		return
	assert(settings.travel_offset != Vector2.ZERO and settings.speed_pixels_per_second > 0)
	var folder: String = (Location as Script).resource_path.get_base_dir() + "/Assets/Elevator/"
	var ambient: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(folder + "ambient.json")
	)
	for definition: Dictionary in ambient.emitters:
		var emitter := Emitter.new()
		add_child(emitter)
		emitter.configure_source(
			definition.duplicate(true),
			self,
			document.gravity,
			random_seed + ambient_emitters.size(),
			folder
		)
		emitter.collision_mask = particle_collision_mask
		emitter.set_animation_visibility(definition.active)
		visuals_by_go[definition.go] = emitter
		ambient_emitters.append(emitter)
	animation.configure(document.default_tracks, visuals_by_go)
	record.waypoints = [[0.0, 0.0], [settings.travel_offset.x, settings.travel_offset.y]]
	record.fields.Speed = settings.speed_pixels_per_second / 16.0
	record.fields.WaitTime = settings.wait_seconds
	record.fields.EaseAmount = settings.ease_amount
	platform = Platform.new()
	platform.use_passenger_adapter = true
	platform.configure(record, null, visual_instances)
	platform.collision_layer = solid_layers
	platform.collision_mask = actor_layers
	add_child(platform)
	for definition: Dictionary in record.child_colliders:
		var body := StaticBody2D.new()
		add_child(body)
		body.transform = Assets.matrix(definition.transform)
		body.collision_layer = solid_layers
		body.collision_mask = actor_layers
		body.set_meta("source_layer", definition.layer)
		body.set_meta("climbable", definition.layer != "HardWall")
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Assets.vec(definition.size)
		shape.shape = box
		shape.position = Assets.vec(definition.offset)
		body.add_child(shape)
		body.reparent(platform, true)
		child_bodies.append(body)
	mechanism = NativeButton.new()
	mechanism.use_host_adapter = true
	mechanism.host_solid_layers = solid_layers
	mechanism.host_actor_layers = actor_layers
	mechanism.actor_eligible = _eligible
	add_child(mechanism)
	var rules: Dictionary = document.rules.duplicate(true)
	rules.door_release_delay = settings.door_release_seconds
	mechanism.configure(
		document.elevator.duplicate(true), self, null, {str(record.id): platform}, rules
	)
	mechanism.interaction_available.connect(_set_available)
	mechanism.projectile_recall_requested.connect(projectile_recall_requested.emit)
	mechanism.gates_changed.connect(doors_changed.emit)
	platform.started.connect(started.emit)
	platform.arrived.connect(arrived.emit)
	platform.passenger_crushed.connect(passenger_crushed.emit)
	if scene_exit_enabled:
		var exit_record: Dictionary = document.scene_exit.duplicate(true)
		exit_record.trigger.transform[4] = settings.scene_exit_offset.x
		exit_record.trigger.transform[5] = settings.scene_exit_offset.y
		exit_record.trigger.size = [settings.scene_exit_size.x, settings.scene_exit_size.y]
		portal = Portal.new()
		portal.accept_actor = _accept_portal_actor
		add_child(portal)
		portal.configure(exit_record, null)
		portal.collision_mask = actor_layers
		portal.requested.connect(_scene_exit)


func bind_passenger(
	actor: CharacterBody2D, shape: CollisionShape2D, can_interact: Callable = Callable()
) -> void:
	assert(actor.is_ancestor_of(shape), "Passenger shape must belong to its actor")
	unbind_passenger()
	actor_ref = weakref(actor)
	eligible = can_interact
	platform.player = actor
	platform.passenger_shape = shape
	mechanism.player = actor


func unbind_passenger() -> void:
	_set_available(actor_ref.get_ref() if actor_ref != null else null, false)
	actor_ref = null
	platform.player = null
	platform.passenger_shape = null
	mechanism.player = null
	eligible = Callable()
	set_passenger_grip(false, false)


func set_passenger_grip(climbing: bool, hanging: bool) -> void:
	platform.passenger_climbing = climbing
	platform.passenger_hanging = hanging


func can_interact(actor: Node) -> bool:
	return is_instance_valid(mechanism) and mechanism.can_interact(actor)


func interact(actor: Node) -> bool:
	return mechanism.interact(actor)


func is_consumed() -> bool:
	return is_instance_valid(mechanism) and mechanism.consumed


func are_doors_closed() -> bool:
	return is_instance_valid(mechanism) and mechanism.doors_closed


func set_motion_scale(value: float) -> void:
	platform.on_source_time_scale(maxf(0, value))


func _eligible() -> bool:
	return not eligible.is_valid() or bool(eligible.call())


func _accept_portal_actor(actor: Node) -> bool:
	return (
		actor_ref != null
		and actor_ref.get_ref() == actor
		and actor.can_process()
		and (actor.collision_layer & actor_layers) != 0
		and _eligible()
	)


func _scene_exit(_record: Dictionary) -> void:
	scene_exit_requested.emit(actor_ref.get_ref(), settings.destination_key)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(mechanism):
		return
	var actor: Node = actor_ref.get_ref() if actor_ref != null else null
	_set_available(actor, can_interact(actor))


func _set_available(actor: Node, value: bool) -> void:
	if available == value:
		return
	available = value
	if outline_tween != null:
		outline_tween.kill()
	assert(document.outline_ease == "OutQuad")
	outline_tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	for id: float in document.outline_ids:
		var visual: Node2D = visuals_by_go[id]
		outline_tween.tween_property(
			visual.material,
			"shader_parameter/base_outline_alpha",
			1.0 if value else 0.0,
			settings.outline_fade_seconds
		)
	interaction_available.emit(actor, value)
