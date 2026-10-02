extends Area2D
## A scene connection is resolved from the source GUID map and build index.
## The enclosing lab owns the fade/load transaction, not this short-lived area.

const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")

signal requested(record: Dictionary)

var source: Dictionary
var player: Node
var pending := false
## Portable hosts can qualify their bound actor without a global player type.
var accept_actor: Callable
var is_loading: Callable
var once := true
var active := true


func configure(record: Dictionary, actor: Node) -> void:
	source = record
	player = actor
	once = bool(record.get("fields", {}).get("once", true))
	transform = Assets.matrix(record.trigger.transform)
	collision_layer = 0
	collision_mask = Collision.PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Assets.vec(record.trigger.size)
	shape.shape = rectangle
	shape.position = Assets.vec(record.trigger.offset)
	add_child(shape)
	body_entered.connect(_enter)


func _enter(body: Node) -> void:
	if pending or not active or (is_loading.is_valid() and bool(is_loading.call())):
		return
	if accept_actor.is_valid():
		if not accept_actor.call(body):
			return
	elif body != player:
		return
	pending = true
	if once:
		active = false
		set_deferred("monitoring", false)
	requested.emit(source)


## Loading is owned by the enclosing host, which may survive this area. A
## repeatable trigger can request again on a later Enter after loading ends.
func finish_request() -> void:
	pending = false


## Matches Trigger.ActivateTrigger / restored collider state. Reactivating an
## overlapping body causes a fresh physics Enter, as source OnEnable does.
func set_active(value: bool) -> void:
	active = value
	pending = false
	set_deferred("monitoring", value)
