extends "BattleWorkshop.gd"
## The host composes a source trigger with the existing two-wave exercise.
## Source level6's full three-wave room is not substituted by this example.
var spawn_requests := 0


func _enter_tree() -> void:
	# Parent enters before its children configure their clocks. Never mutate
	# the shared default Resource or flip on_field after the clock is created.
	$Encounter.settings = $Encounter.settings.duplicate(true)
	$Encounter.settings.on_field = false


func _ready() -> void:
	super._ready()
	$SpawnTrigger.bind_actor(player)
	$SpawnTrigger.spawn_requested.connect(_spawn)
	$SpawnTrigger.entered.connect(func(_actor):
		caption.text = "已进入召唤区域 · 等待 %.2f 秒" % $SpawnTrigger.settings.delay_seconds)
	caption.text = "进入金色区域，触发延迟召唤"


func _spawn() -> void:
	spawn_requests += 1
	encounter.start_spawn()


func _draw() -> void:
	super._draw()
	var trigger: Node2D = $SpawnTrigger
	var settings: Resource = trigger.settings
	draw_set_transform_matrix(trigger.transform * settings.trigger_transform)
	draw_rect(Rect2(settings.trigger_offset - settings.trigger_size / 2, settings.trigger_size),
		Color(0.8, 0.6, 0.2, 0.45), false, 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
