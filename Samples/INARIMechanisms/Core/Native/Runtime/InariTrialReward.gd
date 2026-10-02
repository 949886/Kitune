extends Area2D
## The shipped HiddenItem uses a once-only Trigger and RewardObserver callback,
## not an interaction button. Its collected flag lives in the demo session.
const Assets = preload("OriginalAssets.gd")
const Collision = preload("StudyCollision.gd")
const SourceCurve = preload("UnityCurve.gd")
const ChargePoint = preload("InariChargePoint.gd")
var source: Dictionary
var manager: Node
var stage: Node
var collected := false
var elapsed := 0.0
var visual_nodes: Array[Node] = []
var lights: Dictionary = {}
var charges: Dictionary = {}
## Portable host hooks: no Rossi player fields, scene lighting or save manager.
signal collected_event(actor: Node)
signal currency_requested(actor: Node, amount: int)
signal lights_changed(values: Dictionary)
var use_host_adapter := false
var initially_collected := false
var accept_actor: Callable
var actor_alive: Callable
var target_position: Callable
var actor_layers := 4
var host_units := 16.0
var host_time_scale := 1.0
var random := RandomNumberGenerator.new()


func configure(record: Dictionary, trial: Node) -> void:
	source = record
	manager = trial
	stage = trial.stage
	transform = Assets.matrix(record.trigger.transform)
	collision_layer = 0
	collision_mask = actor_layers if use_host_adapter else Collision.PLAYER
	monitorable = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Assets.vec(record.trigger.size)
	shape.shape = box
	shape.position = Assets.vec(record.trigger.offset)
	add_child(shape)
	for go in record.children:
		if stage.visuals_by_go.has(go):
			visual_nodes.append(stage.visuals_by_go[go])
	collected = (
		initially_collected
		if use_host_adapter
		else manager.session.get(str(source.fields.id), false)
	)
	for item: Dictionary in source.lights:
		lights[item.go] = (
			item.definition.duplicate(true)
			if use_host_adapter
			else stage.data.lights[int(item.index)]
		)
	if collected:
		for visual: Node in visual_nodes:
			visual.hide()
		monitoring = false
		set_process(false)
		for light: Dictionary in lights.values():
			light.enabled = false
		_refresh_lights()
	else:
		for item: Dictionary in source.charges:
			var charge := ChargePoint.new()
			add_child(charge)
			charge.configure(item, self)
			charges[item.go] = charge
	body_entered.connect(_collect)


func _collect(body: Node) -> void:
	if collected:
		return
	if use_host_adapter:
		if not accept_actor.is_valid() or not bool(accept_actor.call(body)):
			return
	elif body != manager.player:
		return
	collected = true
	if not use_host_adapter:
		manager.session[str(source.fields.id)] = true
		manager.session.reward_count = int(manager.session.get("reward_count", 0)) + 1
		# RewardObserver renews the existing level, without raising it as kills do.
		if body.wind_buff.level > 0:
			body.wind_buff.request(body.wind_buff.level)
	set_deferred("monitoring", false)
	stage.animation.release_visuals(source.children)
	_apply_destroy()
	if use_host_adapter:
		collected_event.emit(body)


func _process(delta: float) -> void:
	if not collected:
		return
	elapsed += delta
	_apply_destroy()


func _apply_destroy() -> void:
	var finished := true
	for cache: Dictionary in source.cached:
		var time := minf(elapsed * float(cache.speed), float(cache.state.length))
		finished = finished and time >= float(cache.state.length)
		var visibility: Dictionary = {}
		var enabled_charges: Dictionary = {}
		for item: Dictionary in cache.state.curves:
			var value := SourceCurve.evaluate(item.curve, time)
			# A component's m_Enabled track is not SpriteRenderer visibility.
			# Part_7 is present from t=0 but its homing starts at the last key.
			if (
				item.propertyName == "m_Enabled"
				and item.typeAssemblyQualifiedName.begins_with("ShurikenChargePoint,")
			):
				enabled_charges[item.go] = value >= 0.5
				continue
			if lights.has(item.go):
				if item.propertyName == "m_Intensity":
					lights[item.go].energy = value
				elif item.propertyName == "m_PointLightOuterRadius":
					lights[item.go].radius = (
						value * (host_units if use_host_adapter else manager.player.units)
					)
			var visual: Node = stage.visuals_by_go.get(item.go)
			if visual == null:
				continue
			if visual.has_method("set_source_property"):
				visual.set_source_property(item.propertyName, value)
			match item.propertyName:
				"m_Color.a":
					visual.modulate.a = value
				"m_Enabled":
					visibility[item.go] = value >= 0.5
				"localEulerAnglesRaw.z":
					visual.set_animation_rotation(-deg_to_rad(value))
		for item: Dictionary in cache.state.gameObjectActives:
			var active := SourceCurve.evaluate(item.activeCurve, time) >= 0.5
			if lights.has(item.go):
				lights[item.go].enabled = active
			if active and charges.has(item.go) and enabled_charges.get(item.go, true):
				charges[item.go].activate()
			var visual: Node = stage.visuals_by_go.get(item.go)
			if visual != null:
				var shown: bool = visibility.get(item.go, true) and active
				if visual.has_method("set_animation_visibility"):
					visual.set_animation_visibility(shown)
				else:
					visual.visible = shown
				# Animation changes renderer.enabled, then the charge coroutine may
				# hide it on capture. Preserve that one-time result on later frames.
				if charges.has(item.go) and charges[item.go].finished:
					visual.hide()
	_refresh_lights()
	if finished:
		set_process(false)


func _refresh_lights() -> void:
	if use_host_adapter:
		lights_changed.emit(lights.duplicate(true))
	else:
		stage.lighting.last_center = Vector2.INF
