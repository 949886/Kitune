extends Node
## Shared camera commands, not a replacement Cinemachine renderer. The host
## applies target_state to its own rig; callbacks expose loading/freeze policy.
## Overlapping volumes overwrite one shared state, with no priority/restore stack.
signal soft_zone_changed(unlimited: bool)
const Location = preload("../../PackageLocation.gd")
@export var pixels_per_unit := 16.0
var zones: Array[Node] = []
var player: Node2D
var player_origin: Callable
var loading: Callable
var frozen: Callable
var ignore_exit: Callable
var eligible: Callable
var tracked_offset := Vector3.ZERO
var z_damping := 1.0
var fixed_zone: Node
var pending_entries: Array[Node] = []
var target_position := Vector2.ZERO
var target_depth := 0.0
var soft_deadlines: Array[Dictionary] = []
var unlimited_soft_zone := false
var clock := 0.0
var rules: Dictionary
var last_tick := 0


func _ready() -> void:
	var folder: String = (Location as Script).resource_path.get_base_dir()
	rules = JSON.parse_string(FileAccess.get_file_as_string(folder + "/Assets/CameraZone/device.json")).rules
	last_tick = Time.get_ticks_usec()
	process_priority = 200
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind_actor(actor: Node2D, origin: Callable = Callable(), is_loading: Callable = Callable(), is_frozen: Callable = Callable()) -> void:
	player = actor
	player_origin = origin
	loading = is_loading
	frozen = is_frozen


func accept_actor(body: Node) -> bool:
	return is_instance_valid(player) and body == player and (not eligible.is_valid() or bool(eligible.call()))


func is_loading() -> bool:
	return loading.is_valid() and bool(loading.call())


func origin() -> Vector2:
	return player_origin.call() if player_origin.is_valid() else player.global_position


func enter(zone: Node) -> void:
	if zone.source.kind == "CameraFixTargetTrigger":
		if is_loading(): pending_entries.append(zone)
		else: _enter_fixed(zone)
	else:
		_set_distance(zone)


func leave(zone: Node) -> void:
	if zone.source.kind == "CameraDistanceTrigger":
		tracked_offset = Vector3.ZERO
		z_damping = float(rules.exit_z_damping)
	else:
		fixed_zone = null
		if not is_loading(): _soft_transition(zone)


func _enter_fixed(zone: Node) -> void:
	fixed_zone = zone
	target_position = origin()
	target_depth = 0.0
	_soft_transition(zone)


func _soft_transition(zone: Node) -> void:
	if frozen.is_valid() and bool(frozen.call()): return
	soft_deadlines.append({"owner": weakref(zone), "deadline": clock + float(rules.soft_zone_delay)})
	unlimited_soft_zone = true
	soft_zone_changed.emit(true)


func _set_distance(zone: Node) -> void:
	var value: Dictionary = zone.source.fields.offset
	tracked_offset = Vector3(value.x, value.y, value.z)
	z_damping = float(zone.source.fields.damping)


func _physics_process(_delta: float) -> void:
	refresh_overlaps()


func refresh_overlaps() -> void:
	if not is_instance_valid(player) or not player.can_process(): return
	if not is_loading():
		# The source coroutine survives an exit/once consumption while loading.
		for zone: Node in pending_entries:
			if is_instance_valid(zone): _enter_fixed(zone)
		pending_entries.clear()
	for zone: Node in zones:
		if not is_instance_valid(zone) or not zone.inside or zone.consumed or not zone.active: continue
		if zone.source.kind == "CameraDistanceTrigger":
			_set_distance(zone)
		elif not is_loading():
			fixed_zone = zone
			var point := origin()
			target_position = Vector2(lerpf(zone.global_position.x, point.x, float(zone.source.fields.xDamp)),
				lerpf(zone.global_position.y, point.y, float(zone.source.fields.yDamp)))
			target_depth = float(zone.source.fields.distance)


func _process(_delta: float) -> void:
	var tick := Time.get_ticks_usec()
	advance_realtime((tick - last_tick) / 1000000.0)
	last_tick = tick


## WaitForSecondsRealtime is independent of Engine.time_scale and fixed FPS.
## Injectable advancement also permits deterministic host simulations/tests.
func advance_realtime(delta: float) -> void:
	clock += delta
	for item: Dictionary in soft_deadlines.duplicate():
		if item.owner.get_ref() == null:
			soft_deadlines.erase(item)
		elif clock >= float(item.deadline):
			unlimited_soft_zone = false
			soft_zone_changed.emit(false)
			soft_deadlines.erase(item)


func target_state() -> Dictionary:
	var fixed := is_instance_valid(fixed_zone)
	return {"fixed": fixed, "position": target_position if fixed else origin() + Vector2(tracked_offset.x, -tracked_offset.y) * pixels_per_unit,
		"depth": target_depth if fixed else tracked_offset.z, "z_damping": z_damping,
		"unlimited_soft_zone": unlimited_soft_zone}


func remove_zone(zone: Node) -> void:
	zones.erase(zone)
	while zone in pending_entries: pending_entries.erase(zone)
	if fixed_zone == zone: fixed_zone = null
	for item: Dictionary in soft_deadlines.duplicate():
		if item.owner.get_ref() == zone: soft_deadlines.erase(item)
	# Disabling/destroying a source GameObject stops its own coroutines. All
	# deadlines are canceled when the whole controller/room is freed.
