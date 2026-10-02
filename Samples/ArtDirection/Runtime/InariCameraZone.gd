extends "res://Samples/INARIMechanisms/Devices/CameraZone/CameraZone.gd"
## Original stage placement and physics layer adapter for the shared region.
const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")


func _ready() -> void:
	# The stage configures after insertion; do not create the portable default.
	pass


func configure(record: Dictionary, owner_manager: Node) -> void:
	actor_layers = Collision.PLAYER
	transform = Assets.matrix(record.transform)
	super.configure(record, owner_manager)
