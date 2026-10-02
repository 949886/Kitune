extends Node
## Wind station Animator graph. Sprite references stay discrete; material curves blend.

const Assets = preload("OriginalAssets.gd")
const CurveSampler = preload("OriginalSceneAnimation.gd")

var controller: Dictionary
var visual: Node2D
var defaults: Dictionary
var state := 0
var state_time := 0.0
var transition: Dictionary = {}
var incoming_time := 0.0
var blend_time := 0.0
var triggers: Dictionary = {}
var sampler := CurveSampler.new()


func _init() -> void:
	# Viewport reparenting can exit/re-enter the tree during bloom setup or a level switch.
	# Let normal child ownership release the sampler only when this animator is freed.
	add_child(sampler)
	sampler.set_process(false)


func configure(data: Dictionary, target: Node2D, source_material: Dictionary = {}) -> void:
	controller = data
	visual = target
	state = int(controller.default)
	# Per-station ownership prevents one activation changing the other station.
	visual.material = visual.material.duplicate()
	var source := (
		source_material
		if not source_material.is_empty()
		else Assets.material_info(visual.current_material)
	)
	defaults = {
		"glow_amount": float(source.glow),
		"glow_global": float(source.glow_global),
		"glow_tint": Assets.color(source.glow_color),
		"color_change_new_color": Assets.color(source.color_change.new_color),
	}
	_apply()


func reset() -> void:
	state = int(controller.default)
	state_time = 0.0
	incoming_time = 0.0
	blend_time = 0.0
	transition = {}
	triggers.clear()
	_apply()


func has_left_ready() -> bool:
	return transition.is_empty() and controller.states[state].name != "Ready"


func set_trigger(key: String) -> void:
	triggers[key] = true


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if controller.is_empty():
		return
	# This Animator uses global game time, independently of the player's aim/impact scale.
	if transition.is_empty():
		for candidate: Dictionary in controller.states[state].transitions:
			var requested: bool = candidate.trigger == "" or triggers.has(candidate.trigger)
			var exited: bool = candidate.exit_time == null
			if not exited:
				exited = (
					state_time
					>= float(candidate.exit_time) * float(controller.states[state].length)
				)
			if requested and exited:
				transition = candidate
				triggers.erase(candidate.trigger)
				incoming_time = (
					float(candidate.offset)
					* float(controller.states[int(candidate.destination)].length)
				)
				blend_time = 0.0
				break
	state_time += delta * float(controller.states[state].speed)
	if not transition.is_empty():
		incoming_time += delta * float(controller.states[int(transition.destination)].speed)
		blend_time += delta
		if blend_time >= float(transition.duration):
			state = int(transition.destination)
			state_time = incoming_time
			transition = {}
	_apply()


func _sample(index: int, time: float) -> Dictionary:
	var clip: Dictionary = controller.states[index]
	var local := fposmod(time, float(clip.length)) if clip.loop else minf(time, float(clip.length))
	var values := defaults.duplicate()
	for track: Dictionary in clip.material_tracks:
		var value := sampler._sample(track.keys, local)
		if int(track.component) < 0:
			values[track.uniform] = value
		else:
			var color: Color = values[track.uniform]
			color[int(track.component)] = value
			values[track.uniform] = color
	var sprite: String = clip.frames[0][1]
	for frame: Array in clip.frames:
		if float(frame[0]) > local:
			break
		sprite = frame[1]
	return {"sprite": sprite, "values": values}


func _apply() -> void:
	var pose := _sample(state, state_time)
	if not transition.is_empty():
		var incoming := _sample(int(transition.destination), incoming_time)
		var weight := clampf(blend_time / float(transition.duration), 0.0, 1.0)
		# Sprite references cannot interpolate; choose the dominant state.
		if weight >= 0.5:
			pose.sprite = incoming.sprite
		for uniform_name: String in defaults:
			pose.values[uniform_name] = lerp(
				pose.values[uniform_name], incoming.values[uniform_name], weight
			)
	visual.set_animation_sprite(pose.sprite)
	for uniform_name: String in pose.values:
		visual.material.set_shader_parameter(uniform_name, pose.values[uniform_name])
