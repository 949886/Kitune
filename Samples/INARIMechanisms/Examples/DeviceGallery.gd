extends Node2D
## The gallery is optional; devices never depend on this host or its UI.
const EXHIBITS = [
	preload("SteamJetShowcase.tscn"),
	preload("PlatformWorkshop.tscn"),
	preload("DoorWorkshop.tscn"),
	preload("IceWorkshop.tscn"),
	preload("BreakableDoorWorkshop.tscn"),
	preload("CheckpointHazardWorkshop.tscn"),
	preload("WindWorkshop.tscn"),
	preload("ElevatorWorkshop.tscn"),
	preload("PortalWorkshop.tscn"),
	preload("RewardWorkshop.tscn"),
	preload("TimeTrialWorkshop.tscn"),
	preload("BattleWorkshop.tscn"),
	preload("SpawnWorkshop.tscn"),
	preload("RepeatWorkshop.tscn"),
	preload("ThresholdWorkshop.tscn"),
	preload("SceneObserverWorkshop.tscn"),
	preload("CameraZoneWorkshop.tscn"),
	preload("EnvironmentWorkshop.tscn"),
	preload("ShurikenDistanceWorkshop.tscn"),
	preload("DisappearingPlatformWorkshop.tscn")
]
const TITLES = [
	"教程喷焰装置",
	"拉杆与移动平台",
	"机械门",
	"冰冻装置",
	"可破坏门",
	"存档点与热阱",
	"风增益装置",
	"单次启动电梯",
	"场景切换区域",
	"隐藏奖励与光点",
	"限时挑战",
	"分波封锁房间",
	"区域延迟召唤",
	"重复刷怪",
	"残血增援",
	"事件切场",
	"镜头区域",
	"环境音区域",
	"苦无射程区域",
	"限时消失平台"
]
var exhibit: Node
var chooser: OptionButton


func _ready() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(anchor)
	chooser = OptionButton.new()
	chooser.focus_mode = Control.FOCUS_NONE
	anchor.add_child(chooser)
	chooser.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chooser.position += Vector2(-250, 24)
	chooser.custom_minimum_size = Vector2(220, 40)
	for title: String in TITLES:
		chooser.add_item(title)
	chooser.item_selected.connect(select_exhibit)
	select_exhibit(0)


func select_exhibit(index: int) -> void:
	assert(index >= 0 and index < EXHIBITS.size())
	chooser.select(index)
	if is_instance_valid(exhibit):
		remove_child(exhibit)
		exhibit.queue_free()
	exhibit = EXHIBITS[index].instantiate()
	add_child(exhibit)


## Optional host contract for an exhibit's retry button. Keep the gallery's
## ownership current so switching tabs cannot leave an old retry scene alive.
func replace_exhibit(previous: Node, replacement: Node) -> void:
	assert(previous == exhibit)
	remove_child(previous)
	previous.queue_free()
	exhibit = replacement
	add_child(exhibit)
