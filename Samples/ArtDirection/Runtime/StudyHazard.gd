extends Area2D
## Persistable hazard connection for authored collision scenes.

const Collision = preload("res://Samples/ArtDirection/Runtime/StudyCollision.gd")

var native_spike := false
var spike_damage := 0.0
var feedback_actor: WeakRef
enum ContactRole { NONE, PLAYER, ENEMY }
signal enemy_contact(actor: Node2D)
var use_host_adapter := false
var classify_actor: Callable
var damage_actor: Callable


func configure_spike(amount: float, player: Node) -> void:
	native_spike = true
	spike_damage = amount
	feedback_actor = weakref(player) if is_instance_valid(player) else null
	collision_mask = Collision.PLAYER | Collision.ENEMY_TARGET


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if not native_spike:
		return
	# SettedSpike uses Stay for players: entering while invulnerable must not
	# make the player immune forever while standing inside the same collider.
	for actor: Node2D in get_overlapping_bodies():
		if use_host_adapter:
			if actor.can_process() and classify_actor.call(actor) == ContactRole.PLAYER:
				damage_actor.call(actor, spike_damage)
			continue
		if actor.can_process() and actor.has_method("receive_damage"):
			actor.receive_damage(spike_damage)


func _on_body_entered(actor: Node2D) -> void:
	if native_spike:
		if use_host_adapter:
			if classify_actor.call(actor) == ContactRole.ENEMY:
				damage_actor.call(actor, spike_damage)
				enemy_contact.emit(actor)
			return
		# Enemy damage belongs to Enter only and has no player source, hence no
		# player-kill buff reward. Camera feedback is a separate native event.
		if actor.has_method("receive_study_hit"):
			actor.receive_study_hit({"Damage": spike_damage, "kind": "spike"}, 0.0)
			var player: Node = feedback_actor.get_ref() if feedback_actor != null else null
			if is_instance_valid(player):
				player.camera_shake_requested.emit("Attack")
		return
	if actor.has_method("die"):
		actor.die()
	elif actor.has_method("respawn"):
		actor.respawn()
