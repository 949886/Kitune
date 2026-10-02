extends Node
## Project native parallel and tilted planes around each camera's view center.

var distance := 0.0
var near_clip := 0.0
var far_clip := 0.0
var planes: Dictionary = {}
var camera: Camera2D
var view_center := Vector2.ZERO
var tilted_visuals: Array[Node2D] = []
var authored_offsets: Dictionary = {}


func register_authored(plane: Node2D) -> void:
	var depth := float(plane.get_meta("native_depth"))
	var key := Vector2(depth, 1.0 if plane.get_meta("follow_camera_x", false) else 0.0)
	planes[key] = plane
	authored_offsets[plane] = plane.position


func register_tilted(visual: Node2D, spatial: Dictionary) -> void:
	if spatial.is_empty() or spatial.get("parallel", true):
		return
	visual.configure_perspective(spatial, self)
	tilted_visuals.append(visual)


func configure(source_camera: Dictionary) -> void:
	distance = float(source_camera.distance)
	near_clip = float(source_camera.lens.NearClipPlane)
	far_clip = float(source_camera.lens.FarClipPlane)
	set_process(false)


func parent_for(spatial: Dictionary) -> Node2D:
	if not spatial.get("parallel", false):
		return null

	var depth := float(spatial.depth)
	var follow_x: bool = spatial.get("follow_camera_x", false)
	if is_zero_approx(depth) and not follow_x:
		return null

	var key := Vector2(depth, 1.0 if follow_x else 0.0)
	if not planes.has(key):
		var plane := Node2D.new()
		var camera_distance := distance + depth
		plane.visible = camera_distance >= near_clip and camera_distance <= far_clip

		# Unity faces +Z. Relative to the gameplay plane at Z=0, a rear plane
		# shrinks by D / (D + Z). Camera2D zoom still controls reference framing.
		var factor := distance / camera_distance if plane.visible else 1.0
		plane.scale = Vector2.ONE * factor
		plane.set_meta("follow_camera_x", follow_x)
		_position_plane(plane)
		add_child(plane)
		planes[key] = plane

	return planes[key]


func attach_camera(value: Camera2D) -> void:
	camera = value
	# The camera rig updates at priority 300; read its completed view afterward.
	process_priority = 400
	set_distance(float(camera.get_meta("source_camera_distance", distance)))
	update_center(camera.get_screen_center_position())
	set_process(true)


func _process(_delta: float) -> void:
	if is_instance_valid(camera):
		set_distance(float(camera.get_meta("source_camera_distance", distance)))
		update_center(camera.get_screen_center_position())


func set_distance(value: float) -> void:
	if is_equal_approx(distance, value):
		return
	distance = value
	for key: Vector2 in planes:
		var plane: Node2D = planes[key]
		var depth := distance + key.x
		plane.visible = depth >= near_clip and depth <= far_clip
		plane.scale = Vector2.ONE * (distance / depth if plane.visible else 1.0)
		_position_plane(plane)
	for visual: Node2D in tilted_visuals:
		if is_instance_valid(visual):
			visual.queue_redraw()


func update_center(center: Vector2) -> void:
	if view_center.is_equal_approx(center):
		return
	view_center = center

	# Move the shared plane, leaving sprite animation and local offsets intact.
	for plane: Node2D in planes.values():
		_position_plane(plane)
	for visual: Node2D in tilted_visuals:
		if is_instance_valid(visual):
			visual.queue_redraw()


func _position_plane(plane: Node2D) -> void:
	plane.position = view_center * (1.0 - plane.scale.x)
	if plane.get_meta("follow_camera_x", false):
		plane.position.x += view_center.x * plane.scale.x
	plane.position += authored_offsets.get(plane, Vector2.ZERO)
