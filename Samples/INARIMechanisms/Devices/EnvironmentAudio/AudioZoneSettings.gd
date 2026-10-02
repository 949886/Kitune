extends "../../Core/TriggerSettings.gd"
## Raw source units are converted to pixel geometry by the exporter. Trigger
## transforms remain host placement; source_transform is optional evidence.
@export_enum("ambient", "bgm", "reverb") var family := "ambient"
@export var event_guid := ""
@export var parameters: Dictionary = {}
