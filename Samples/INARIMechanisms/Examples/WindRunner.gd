extends "WorkshopPlayer.gd"
## Example host owns stamina, story healing, spawn state and horizontal motion.
@export var base_speed := 180.0
@export var maximum_stamina := 100.0
@export var maximum_health := 100.0
@onready var buff: Node = $WindBuff
var stamina := 1.0
var health := 1.0
var story_mode := false
var spawning := false
var feedback_count := 0


func _ready() -> void:
	buff.stamina_feedback_requested.connect(_buff_feedback)


func _physics_process(delta: float) -> void:
	if spawning:
		return
	speed = base_speed + buff.extra_speed
	modulate = (
		Color.WHITE.lerp(Color("ffa764"), 1.0 - buff.ratio) if buff.level > 0 else Color.WHITE
	)
	super._physics_process(delta)


func is_spawning() -> bool:
	return spawning


func add_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0, maximum_stamina)


func heal_story(amount: int) -> void:
	if story_mode:
		health = minf(maximum_health, health + amount)


func _buff_feedback(current_level: int, previous_level: int) -> void:
	# Native material/trail effects belong to the actual character renderer.
	# This simple host records only eligible feedback; it does not imitate them.
	if current_level >= previous_level:
		feedback_count += 1


func station_feedback() -> void:
	_buff_feedback(buff.level, buff.state.previous_level)
