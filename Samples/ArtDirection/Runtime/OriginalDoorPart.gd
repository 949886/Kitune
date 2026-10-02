extends StaticBody2D
## All fragments of a source door forward interaction to the same door instance.

var door: Node


func receive_study_hit(hit: Dictionary, facing: float) -> void:
	if is_instance_valid(door):
		door.interact(int(hit.get("interaction", 4)), facing)
