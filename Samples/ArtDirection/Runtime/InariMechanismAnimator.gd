extends Node
## Trigger-driven source controllers. Visual tracks remain in original world
## sorting nodes, so opening doors can animate while their cabin also moves.

const Tracks = preload("res://Samples/ArtDirection/Runtime/OriginalSceneAnimation.gd")

var source: Dictionary
var visuals: Dictionary
var tracks := Tracks.new()
var state := -1
var elapsed := 0.0


func configure(record: Dictionary, stage: Node) -> void:
	source = record
	visuals = stage.visuals_by_go
	add_child(tracks)
	if source.is_empty():
		return
	stage.animation.release_visuals(source.children)
	play(int(source.default))


func trigger(parameter: String) -> void:
	# Source code also sends Interact to controllers with no such transition.
	if source.is_empty() or not source.triggers.has(parameter):
		return
	play(int(source.triggers[parameter].m_DestinationState))


func play(index: int) -> void:
	state = index
	elapsed = 0.0
	tracks.tracks.clear()
	tracks.configure(source.states[state].tracks, visuals)


func _process(delta: float) -> void:
	if state < 0:
		return
	elapsed += delta
	var definition: Dictionary = source.states[state]
	if definition.transitions.is_empty():
		return
	var transition: Dictionary = definition.transitions[0]
	var duration := float(transition.m_TransitionDuration)
	if not transition.m_HasFixedDuration:
		duration *= float(definition.length)
	if elapsed >= float(transition.m_ExitTime) * float(definition.length) + duration:
		play(int(transition.m_DestinationState))
