extends "PortalRoom.gd"
## Host assembly: attack a real reusable lever to send the event. Original
## incoming calls come from cutscene completion, whose Timeline is not ported.
@export var return_to_menu := false
@onready var observer: Node = get_node_or_null("Observer")
@onready var lever: Node = get_node_or_null("Lever")
