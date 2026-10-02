extends Node2D
## This persistent host owns room PackedScenes and actor policy. The portable
## trigger carries semantic destination keys; it never imports these examples.
const FIRST = preload("PortalRoomA.tscn")
@export var initial_scene: PackedScene = FIRST
@export var title_text := "INARI · 场景切换区域"
@export_multiline var instruction_text := "A / D 移动 · 空格跳跃 · 向右进入青色区域\n第一次过渡会继续向右走；第二次停下等待。R 重新体验。"
@export var destinations: Dictionary[String, PackedScene] = {
	"level12": preload("PortalRoomB.tscn"), "level27": preload("PortalRoomC.tscn")
}
@onready var player: CharacterBody2D = $Player
@onready var transition: CanvasLayer = $Transition
var room: Node2D
var caption: Label
var completed := false
var swaps := 0
var previous_room: WeakRef


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	var ui := CanvasLayer.new()
	ui.layer = 21
	add_child(ui)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	ui.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var help := Label.new()
	help.text = instruction_text
	box.add_child(help)
	caption = Label.new()
	box.add_child(caption)
	transition.began.connect(_began)
	transition.covered.connect(_covered)
	transition.loaded.connect(_loaded)
	transition.finished.connect(_finished)
	transition.cancelled.connect(_cancelled)
	_install(initial_scene)


func _install(scene: PackedScene) -> void:
	if is_instance_valid(room):
		previous_room = weakref(room)
		remove_child(room)
		room.queue_free()
	room = scene.instantiate()
	add_child(room)
	move_child(room, 0)
	player.position = room.spawn
	player.velocity = Vector2.ZERO
	if room.portal != null:
		room.portal.bind_actor(player, Callable(), transition.is_loading)
		room.portal.transition_requested.connect(_requested)
	caption.text = room.title


func _requested(actor: Node2D, data: Dictionary) -> void:
	assert(destinations.has(data.destination), "Host must map the semantic destination key")
	transition.request(actor, data)


func _began(actor: Node2D, data: Dictionary, _ticket: int) -> void:
	actor.begin_transition(data)
	caption.text = "正在离开房间：" + ("继续向右移动" if data.maintain_input else "停下等待")


func _covered(data: Dictionary, ticket: int) -> void:
	# Scene replacement is deferred out of physics/signal dispatch. Real hosts
	# may load asynchronously and call finish_load(ticket) after their own work.
	call_deferred("_swap", data, ticket)


func _swap(data: Dictionary, ticket: int) -> void:
	if transition.ticket != ticket or transition.phase != transition.Phase.COVERED:
		return
	_install(destinations[data.destination])
	swaps += 1
	transition.finish_load(ticket)


func _loaded(_data: Dictionary, _ticket: int) -> void:
	player.scene_loaded()


func _finished(_data: Dictionary, _ticket: int) -> void:
	player.end_transition()
	completed = room.portal == null
	caption.text = room.title


func _cancelled(_data: Dictionary, _ticket: int) -> void:
	if is_instance_valid(player):
		player.end_transition()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		transition.cancel()
		completed = false
		swaps = 0
		_install(initial_scene)
