extends "BattleWorkshop.gd"
## Actual source four-wave/75% composition with training actors. The selected
## target uses four HP so one ordinary physical hit visibly reaches the ratio.
## Source SwordMan/SpikeMan AI and the final Timeline are separate work.
@export var selected_target_health := 4
@export var selected_target_color := Color("c36a96")


func _ready() -> void:
	super._ready()
	contact.contacted.connect(func(_actor): encounter.start_spawn())
	for key: String in encounter.settings.thresholds:
		var target: Node2D = enemies[key]
		target.max_health = selected_target_health
		target.health = selected_target_health
		target.body_color = selected_target_color
		target.damaged.connect(func(actor, ratio): encounter.notify_damaged(key, actor, ratio))
	caption.text = "进入房间启动四波战斗 · 紫色目标残血后会呼叫增援"
