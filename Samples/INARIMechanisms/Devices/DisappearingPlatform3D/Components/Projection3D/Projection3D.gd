@tool
class_name Projection3D
extends Node2D
## Projects an injected 3D scene into this Node2D's canvas.
## All generated infrastructure is internal and unowned; only this node and its exports
## are serialized. Scene-specific animation/gameplay belongs to the injected scene.

signal rebuilding
signal rebuilt
signal build_failed(message: String)

@export_category("Content")
## The injected scene must have a Node3D root. Null means an empty projection.
@export var scene: PackedScene:
	set(value):
		if scene == value:
			return
		if scene != null and scene.changed.is_connected(_on_scene_changed):
			scene.changed.disconnect(_on_scene_changed)
		scene = value
		if scene != null:
			scene.changed.connect(_on_scene_changed)
		_on_scene_changed()

## Applied to the generated Scene3D container, preserving the scene root's transform.
@export var scene_transform: Transform3D = Transform3D.IDENTITY:
	set(value):
		scene_transform = value
		if is_instance_valid(_scene_container):
			_scene_container.transform = value
		_request_config_redraw()

@export_category("Viewport")
@export var viewport_size: Vector2i = Vector2i(169, 109):
	set(value):
		viewport_size = Vector2i(maxi(value.x, 2), maxi(value.y, 2))
		if is_instance_valid(_viewport):
			_viewport.size = viewport_size
		_request_config_redraw()

@export var viewport_update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_WHEN_VISIBLE:
	set(value):
		viewport_update_mode = value
		if is_instance_valid(_viewport):
			_viewport.render_target_update_mode = value

@export_category("Orthographic Camera")
@export_range(0.001, 10000.0, 0.001, "or_greater") var camera_size: float = 109.0:
	set(value):
		camera_size = maxf(value, 0.001)
		if is_instance_valid(_camera):
			_camera.size = camera_size
		_request_config_redraw()

@export var camera_position: Vector3 = Vector3(-2.5, -15.5, 500.0):
	set(value):
		camera_position = value
		if is_instance_valid(_camera):
			_camera.position = value
		_request_config_redraw()

## Euler angles in radians, just like Node3D.rotation.
@export var camera_rotation: Vector3 = Vector3.ZERO:
	set(value):
		camera_rotation = value
		if is_instance_valid(_camera):
			_camera.rotation = value
		_request_config_redraw()

@export var camera_keep_aspect: Camera3D.KeepAspect = Camera3D.KEEP_HEIGHT:
	set(value):
		camera_keep_aspect = value
		if is_instance_valid(_camera):
			_camera.keep_aspect = value
		_request_config_redraw()

@export_range(0.001, 1000.0, 0.001, "or_greater") var camera_near: float = 0.05:
	set(value):
		camera_near = maxf(value, 0.001)
		_apply_camera_clip()

@export_range(0.002, 10000.0, 0.001, "or_greater") var camera_far: float = 1000.0:
	set(value):
		camera_far = maxf(value, 0.002)
		_apply_camera_clip()

@export_category("Display")
@export var sprite_position: Vector2 = Vector2(-87.0, -39.0):
	set(value):
		sprite_position = value
		if is_instance_valid(_sprite):
			_sprite.position = value

@export var sprite_centered: bool = false:
	set(value):
		sprite_centered = value
		if is_instance_valid(_sprite):
			_sprite.centered = value

@export var sprite_texture_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_NEAREST:
	set(value):
		sprite_texture_filter = value
		if is_instance_valid(_sprite):
			_sprite.texture_filter = value

@export_category("Environment And Light")
## Optional template. A private deep duplicate is assigned to this instance's
## camera. Null uses a transparent background and soft, cool ambient lighting.
@export var environment: Environment:
	set(value):
		if environment == value:
			return
		if environment != null and environment.changed.is_connected(_apply_environment):
			environment.changed.disconnect(_apply_environment)
		environment = value
		if environment != null:
			environment.changed.connect(_apply_environment)
		_apply_environment()

@export var light_rotation: Vector3 = Vector3(-0.4363323129, -0.5235987756, 0.0):
	set(value):
		light_rotation = value
		if is_instance_valid(_light):
			_light.rotation = value
		_request_config_redraw()

@export var light_color: Color = Color.WHITE:
	set(value):
		light_color = value
		if is_instance_valid(_light):
			_light.light_color = value
		_request_config_redraw()

@export_range(0.0, 16.0, 0.01, "or_greater") var light_energy: float = 1.1:
	set(value):
		light_energy = maxf(value, 0.0)
		if is_instance_valid(_light):
			_light.light_energy = light_energy
		_request_config_redraw()

@export var light_shadow_enabled: bool = false:
	set(value):
		light_shadow_enabled = value
		if is_instance_valid(_light):
			_light.shadow_enabled = value
		_request_config_redraw()

## Generated-node accessors. Call ensure_built() before using them from another
## node's _enter_tree/_ready, and refresh references in the rebuilt signal.
var viewport: SubViewport:
	get:
		return _viewport if is_instance_valid(_viewport) else null
var camera: Camera3D:
	get:
		return _camera if is_instance_valid(_camera) else null
var sprite: Sprite2D:
	get:
		return _sprite if is_instance_valid(_sprite) else null
var scene_container: Node3D:
	get:
		return _scene_container if is_instance_valid(_scene_container) else null
var scene_instance: Node3D:
	get:
		return _scene_instance if is_instance_valid(_scene_instance) else null
var light: DirectionalLight3D:
	get:
		return _light if is_instance_valid(_light) else null

var _viewport: SubViewport
var _camera: Camera3D
var _sprite: Sprite2D
var _scene_container: Node3D
var _scene_instance: Node3D
var _light: DirectionalLight3D
var _scene_dirty: bool = true
var _build_pending: bool = false
var _building: bool = false
var _last_build_error: String = ""


func _enter_tree() -> void:
	# Retain internals when temporarily detached/reparented. They re-enter with us.
	# A deferred call also handles export assignment while the tree is busy loading.
	_queue_build()


func _ready() -> void:
	ensure_built()


## Idempotent. Does not overwrite direct camera/model changes when already built.
## May be called before this node enters the tree.
func ensure_built() -> bool:
	if _building:
		return false
	if not _scene_dirty and _pipeline_is_valid():
		return true
	# Avoid repeatedly instantiating an unchanged invalid scene every frame.
	if not _scene_dirty and not _last_build_error.is_empty():
		return false
	return rebuild()


## Synchronously replaces all generated nodes and content. References previously
## obtained through the accessors must be refreshed after rebuilt is emitted.
func rebuild() -> bool:
	if _building:
		return false
	_building = true
	_scene_dirty = false
	_last_build_error = ""
	rebuilding.emit()
	_teardown()

	var content: Node3D
	if scene != null:
		if not scene.can_instantiate():
			return _fail_build("Projection3D.scene is empty and cannot be instantiated.")
		var candidate: Node = scene.instantiate()
		if not candidate is Node3D:
			var actual_type: String = candidate.get_class() if candidate != null else "null"
			if candidate != null:
				candidate.free()
			return _fail_build("Projection3D.scene must have a Node3D root; received %s." % actual_type)
		content = candidate as Node3D
		_sanitize_content_ownership(content)

	_viewport = SubViewport.new()
	_viewport.name = "Viewport3D"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.gui_disable_input = true
	_viewport.size = viewport_size
	_viewport.render_target_update_mode = viewport_update_mode
	add_child(_viewport, false, Node.INTERNAL_MODE_BACK)

	_scene_container = Node3D.new()
	_scene_container.name = "Scene3D"
	_scene_container.transform = scene_transform
	_viewport.add_child(_scene_container, false, Node.INTERNAL_MODE_BACK)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = camera_position
	_camera.rotation = camera_rotation
	_camera.size = camera_size
	_camera.keep_aspect = camera_keep_aspect
	_apply_camera_clip()
	_apply_environment()
	_viewport.add_child(_camera, false, Node.INTERNAL_MODE_BACK)
	_camera.current = true

	_light = DirectionalLight3D.new()
	_light.name = "DirectionalLight3D"
	_light.rotation = light_rotation
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.shadow_enabled = light_shadow_enabled
	_viewport.add_child(_light, false, Node.INTERNAL_MODE_BACK)

	_sprite = Sprite2D.new()
	_sprite.name = "Projected3D"
	_sprite.position = sprite_position
	_sprite.centered = sprite_centered
	_sprite.texture_filter = sprite_texture_filter
	_sprite.texture = _viewport.get_texture()
	add_child(_sprite, false, Node.INTERNAL_MODE_BACK)

	# Inject content last: its _enter_tree/_ready can already find a current
	# camera and a complete viewport/display pipeline.
	if content != null:
		_scene_instance = content
		_scene_container.add_child(content, false, Node.INTERNAL_MODE_BACK)
		# Tool scripts can assign owners during _enter_tree or _ready.
		_sanitize_content_ownership(content)
	# A scene may contain its own current camera; this component owns projection.
	_camera.current = true

	_building = false
	update_configuration_warnings()
	rebuilt.emit()
	return true


func _fail_build(message: String) -> bool:
	_last_build_error = message
	_building = false
	update_configuration_warnings()
	push_warning(message)
	build_failed.emit(message)
	return false


func _on_scene_changed() -> void:
	_scene_dirty = true
	_last_build_error = ""
	_queue_build()
	update_configuration_warnings()


func _queue_build() -> void:
	if not is_inside_tree() or _build_pending:
		return
	_build_pending = true
	_build_deferred.call_deferred()


func _build_deferred() -> void:
	_build_pending = false
	if is_inside_tree():
		ensure_built()


func _pipeline_is_valid() -> bool:
	return (
		is_instance_valid(_viewport)
		and is_instance_valid(_camera)
		and is_instance_valid(_sprite)
		and is_instance_valid(_scene_container)
		and is_instance_valid(_light)
		and _viewport.get_parent() == self
		and _sprite.get_parent() == self
		and _camera.get_parent() == _viewport
		and _light.get_parent() == _viewport
		and _scene_container.get_parent() == _viewport
		and (scene == null or (
			is_instance_valid(_scene_instance)
			and _scene_instance.get_parent() == _scene_container
		))
	)


func _apply_camera_clip() -> void:
	if is_instance_valid(_camera):
		_camera.near = camera_near
		_camera.far = maxf(camera_far, camera_near + 0.001)
	_request_config_redraw()
	update_configuration_warnings()


func _apply_environment() -> void:
	if not is_instance_valid(_camera):
		return
	var instance_environment: Environment
	if environment != null:
		instance_environment = environment.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as Environment
	else:
		instance_environment = Environment.new()
		instance_environment.background_mode = Environment.BG_CLEAR_COLOR
		instance_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		instance_environment.ambient_light_color = Color(0.68, 0.74, 0.8, 1.0)
		instance_environment.ambient_light_energy = 0.8
	_camera.environment = instance_environment
	_request_config_redraw()


## Explicitly render one frame if rendering is currently disabled (including an
## already consumed UPDATE_ONCE). Continuous/visible update modes stay unchanged.
## This explicit request also works when viewport_update_mode is UPDATE_DISABLED.
func request_redraw() -> void:
	if is_instance_valid(_viewport) and _viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _request_config_redraw() -> void:
	# Disabled is an intentional policy; only an explicit request overrides it.
	if viewport_update_mode != SubViewport.UPDATE_DISABLED:
		request_redraw()


func _teardown() -> void:
	# Release every owned node, even if a consumer detached one through an accessor.
	# Authored children of this component are never included in this list.
	if is_instance_valid(_sprite):
		_sprite.texture = null
	# Accessors normalize freed references to null. Read each immediately before
	# use, since freeing one node may also free another that was reparented into it.
	_free_generated_node(sprite)
	_free_generated_node(scene_instance)
	_free_generated_node(camera)
	_free_generated_node(light)
	_free_generated_node(scene_container)
	_free_generated_node(viewport)
	_sprite = null
	_viewport = null
	_camera = null
	_light = null
	_scene_container = null
	_scene_instance = null


func _free_generated_node(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _sanitize_content_ownership(content_root: Node) -> void:
	# The unowned internal root is the serialization boundary. Descendants retain
	# their native scene owners so %UniqueName and nested-scene scopes still work.
	content_root.owner = null
	_clear_external_owners(content_root, content_root)


func _clear_external_owners(node: Node, content_root: Node) -> void:
	if node.owner != null and node.owner != content_root and not content_root.is_ancestor_of(node.owner):
		node.owner = null
	for child: Node in node.get_children(true):
		_clear_external_owners(child, content_root)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not _last_build_error.is_empty():
		warnings.append(_last_build_error)
	if camera_far <= camera_near:
		warnings.append("Camera far must exceed camera near; the effective far plane is clamped.")
	return warnings
