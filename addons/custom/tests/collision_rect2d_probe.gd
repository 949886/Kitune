extends SceneTree
## Regression probe for collision, scene persistence and transformed resize handles.
## Run with Godot --headless --path <project> --script <this file> --fixed-fps 60.

const CollisionRect := preload("res://addons/custom/collision_rect2d.gd")
const Overlay := preload("res://addons/custom/collision_rect2d_overlay.gd")


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func has_body_at(fixture: Node2D, point: Vector2, body: StaticBody2D) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	for hit in fixture.get_world_2d().direct_space_state.intersect_point(query):
		if hit.collider == body:
			return true
	return false


func check_handles() -> void:
	var overlay := Overlay.new(null)
	var rect := CollisionRect.new()
	var unrelated := Node2D.new()
	assert(overlay.handles(rect) and not overlay.handles(unrelated))
	assert(not overlay.handles(null))
	# The opposite corner/edge must remain fixed in parent space, even with
	# rotation and nonuniform scale. Exercise all eight handles independently.
	var original := Transform2D(0.4, Vector2(1.5, 0.75), 0.0, Vector2(50, 80))
	var original_size := Vector2(100, 40)
	for handle in Overlay.HANDLE_DIRECTIONS:
		var direction: Vector2 = Overlay.HANDLE_DIRECTIONS[handle]
		overlay._drag_handle = handle
		overlay._drag_start_size = original_size
		overlay._drag_start_transform = original
		var result: Dictionary = overlay._build_drag_result(direction * Vector2(80, 45))
		var new_size: Vector2 = result.size
		var resized := original
		resized.origin = result.position
		var anchor := -direction * original_size * 0.5
		var new_anchor := -direction * new_size * 0.5
		assert((original * anchor).is_equal_approx(resized * new_anchor))
		if direction.x == 0.0:
			assert(is_equal_approx(new_size.x, original_size.x))
		if direction.y == 0.0:
			assert(is_equal_approx(new_size.y, original_size.y))
		# Drag past the opposite edge: the result must remain a valid rectangle.
		result = overlay._build_drag_result(-direction * Vector2(500, 500))
		new_size = result.size
		assert(new_size.x >= CollisionRect.MIN_SIZE and new_size.y >= CollisionRect.MIN_SIZE)
		resized.origin = result.position
		new_anchor = -direction * new_size * 0.5
		assert((original * anchor).is_equal_approx(resized * new_anchor))
	# Applying the result also updates the node's center and exported dimensions.
	overlay._apply_resize(rect, Vector2(150, 60), Vector2(75, 90))
	assert(rect.size == Vector2(150, 60) and rect.position == Vector2(75, 90))
	rect.free()
	unrelated.free()


func run() -> void:
	check_handles()
	var fixture := Node2D.new()
	root.add_child(fixture)
	var rect := CollisionRect.new()
	rect.size = Vector2(120, 40)
	rect.fill_color = Color.CORNFLOWER_BLUE
	rect.edge_color = Color.WHITE
	rect.edge_width = 6.0
	fixture.add_child(rect)
	var other := CollisionRect.new()
	other.position = Vector2(1000, 0)
	fixture.add_child(other)
	await frames(3)
	var collider: CollisionShape2D = rect.get_node("CollisionShape2D")
	assert(collider.shape.size == rect.size)
	assert(collider.shape != other.get_node("CollisionShape2D").shape)
	assert(has_body_at(fixture, Vector2(55, 0), rect))
	assert(not has_body_at(fixture, Vector2(65, 0), rect))

	# Resize from a real physics query callback, as tutorial signals can do.
	var entered: Array[Node2D] = []
	var area := Area2D.new()
	var area_collider := CollisionShape2D.new()
	var area_shape := RectangleShape2D.new()
	area_shape.size = Vector2(10, 10)
	area_collider.shape = area_shape
	area.add_child(area_collider)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body == rect:
			rect.size = Vector2(180, 70)
			entered.append(body)
	)
	fixture.add_child(area)
	await frames(4)
	assert(entered.has(rect), "The probe must exercise a real body_entered callback")
	assert(collider.shape.size == rect.size)
	assert(has_body_at(fixture, Vector2(80, 0), rect))
	assert(not has_body_at(fixture, Vector2(95, 0), rect))
	assert(other.size == Vector2(128, 32))
	assert(other.get_node("CollisionShape2D").shape.size == other.size)

	# Only exported properties are saved. Loading recreates exactly one collider.
	var packed := PackedScene.new()
	assert(packed.pack(rect) == OK)
	var restored: CollisionRect = packed.instantiate()
	restored.position = Vector2(2000, 0)
	fixture.add_child(restored)
	await frames(3)
	assert(restored.get_child_count() == 1)
	assert(restored.get_node("CollisionShape2D").shape.size == rect.size)
	assert(restored.fill_color == rect.fill_color and restored.edge_color == rect.edge_color)
	assert(restored.edge_width == rect.edge_width)
	assert(has_body_at(fixture, Vector2(2080, 0), restored))
	restored.size = Vector2(-1, 0)
	await frames(2)
	assert(restored.size == Vector2.ONE * CollisionRect.MIN_SIZE)
	assert(restored.get_node("CollisionShape2D").shape.size == restored.size)
	fixture.queue_free()
	await process_frame

	# Load after autoload initialization for the tutorial's typed player scripts.
	var tutorial: Node2D = load("res://Game/Tutorial/TutorialIntro.tscn").instantiate()
	root.add_child(tutorial)
	await frames(3)
	var migrated_count := 0
	for body in tutorial.find_children("*", "StaticBody2D", true, false):
		if body.get_script() == CollisionRect:
			migrated_count += 1
			assert(body.get_node("CollisionShape2D").shape.size == body.size)
	assert(migrated_count == 6, "All six tutorial platforms must use CollisionRect2D")
	tutorial.queue_free()
	await process_frame
	print("COLLISION_RECT_2D_PASS: physics resize, persistence, 8 handles, 6 tutorial platforms")
	quit()
