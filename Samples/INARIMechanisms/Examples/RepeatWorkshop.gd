extends Node2D
## Host composition: real physics attacks, death hooks, factory and cleanup.
## Original enemy AI/art are intentionally separate from the reusable device.
const Target = preload("RepeatTarget.gd")
@onready var spawner: Node2D = $Spawner
@onready var player: CharacterBody2D = $Player
var targets: Dictionary = {}
var replacements := 0
var removed_persistence := 0
var caption: Label


func _ready() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(512, 288)
	camera.zoom = Vector2.ONE * get_viewport_rect().size.y / 576.0
	# Translate the original group as a whole to the example's floor. Keep
	# authored relative respawn positions and delays in the exported Resource.
	var first: String = spawner.settings.placements.keys()[0]
	spawner.position = $SpawnAnchor.position - Vector2(spawner.settings.placements[first])
	spawner.flags_requested.connect(func(actor, repeated, loaded):
		actor.repeated = repeated
		actor.loaded = loaded)
	spawner.persistence_remove_requested.connect(func(_actor): removed_persistence += 1)
	spawner.member_registered.connect(_registered)
	for kind: String in spawner.settings.kinds.values():
		spawner.register_factory(kind, _make_target)
	for key: String in spawner.settings.kinds:
		var binding := _make_target(spawner.to_global(spawner.settings.placements[key]))
		_wire(key, binding.actor)
		spawner.bind_enemy(key, binding.actor, binding.idle, binding.tint)
	var ui := CanvasLayer.new()
	add_child(ui)
	var column := VBoxContainer.new()
	column.position = Vector2(24, 20)
	ui.add_child(column)
	var title := Label.new()
	title.text = "INARI · 重复刷怪"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var help := Label.new()
	help.text = "A / D 移动 · 空格跳跃 · J 普通攻击 / K 重击 · R 重试\n击败目标后等待 %.1f 秒；新目标用 %.1f 秒淡入，可反复挑战。" % [spawner.settings.wait_seconds, spawner.settings.fade_seconds]
	column.add_child(help)
	caption = Label.new()
	column.add_child(caption)


func _make_target(point: Vector2) -> Dictionary:
	var actor := Target.new()
	add_child(actor)
	actor.global_position = point
	actor.set_active(true)
	return {"actor": actor, "idle": actor.force_idle, "tint": actor.apply_tint}


func _wire(key: StringName, actor: Node2D) -> void:
	targets[key] = actor
	actor.defeated.connect(func(dead_actor): spawner.notify_defeated(key, dead_actor))


func _registered(key: StringName, actor: Node2D) -> void:
	replacements += 1
	_wire(key, actor)


func _process(_delta: float) -> void:
	caption.text = "已重生 %d 次" % replacements
	if not spawner.waiting.is_empty():
		var wait: Dictionary = spawner.waiting[0]
		var remaining := maxf(0, float(wait.deadline) - spawner.realtime) if float(wait.deadline) >= 0 else float(wait.duration)
		caption.text += " · 距离下次重生 %.1f 秒" % remaining


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		call_deferred("_restart")


func _restart() -> void:
	var replacement: Node = load(scene_file_path).instantiate()
	if get_parent().has_method("replace_exhibit"):
		get_parent().replace_exhibit(self, replacement)
	else:
		get_parent().add_child(replacement)
		queue_free()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1024, 576), Color("121820"))
	draw_rect(Rect2(0, 400, 1024, 48), Color("39474e"))
