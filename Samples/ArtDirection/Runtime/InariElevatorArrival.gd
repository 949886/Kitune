extends Node
## The native destination scene auto-plays a Timeline, not a PlatformController.
## Evaluate its exported cubic motion for the cabin, doors and bound player;
## completion follows the source TimelineCompleteCommand marker.

signal finished

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const Sampler = preload("res://Samples/ArtDirection/Runtime/OriginalSceneAnimation.gd")

var source: Dictionary
var player: Node
var stage: Node
var active := true
var clock := 0.0
var groups: Dictionary = {}
var sampler := Sampler.new()
var player_origin := Vector2.ZERO
var originals: Dictionary = {}
var audio_handles: Dictionary = {}


func configure(record: Dictionary, owner_stage: Node, actor: Node) -> void:
	source = record
	stage = owner_stage
	player = actor
	add_child(sampler)
	sampler.set_process(false)
	stage.animation.release_visuals(source.extra_visuals)
	for clip: Dictionary in source.tracks:
		var key := "%s:%s:%s" % [clip.track, clip.go, clip.kind]
		if not groups.has(key):
			groups[key] = {"clips": [], "nodes": []}
		groups[key].clips.append(clip)
	for group: Dictionary in groups.values():
		group.clips.sort_custom(func(a, b): return a.start < b.start)
		var first: Dictionary = group.clips[0]
		if first.player:
			player_origin = player.position - _position(first, 0.0)
			continue
		var ids: Array = first.children.map(func(value): return int(value))
		for visual: Node2D in stage.visual_instances:
			if int(visual.data.get("go", visual.data.get("tilemap_go", -1))) in ids:
				group.nodes.append(visual)
		# The native animated parent also moves the original collision shapes.
		for node: Node in stage.get_children():
			if node is CollisionObject2D and int(node.get_meta("source_go", -1)) in ids:
				group.nodes.append(node)
		for node: Node2D in group.nodes:
			originals[node] = {"position": node.position, "rotation": node.rotation}
	player.process_mode = Node.PROCESS_MODE_DISABLED
	advance(0.0)


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	clock = minf(clock + delta, float(source.duration))
	for node: Node2D in originals:
		node.position = originals[node].position
		node.rotation = originals[node].rotation
	for group: Dictionary in groups.values():
		var clip: Dictionary = group.clips[0]
		for candidate: Dictionary in group.clips:
			if float(candidate.start) <= clock:
				clip = candidate
		if clip.player:
			player.position = player_origin + _position(clip, clock)
		elif clip.kind == "position":
			var offset := _position(clip, clock)
			for node: Node2D in group.nodes:
				node.position += offset
		elif clip.kind == "rotation":
			var angle := sampler._sample(clip.axes[2], _local_time(clip, clock))
			for node: Node2D in group.nodes:
				node.rotation -= deg_to_rad(angle)
	player.sprite.advance(delta)
	for index in source.audio.size():
		var sound: Dictionary = source.audio[index]
		if clock >= float(sound.start) and not audio_handles.has(index):
			audio_handles[index] = stage.audio.play_event(sound.group, self)
		if clock >= float(sound.start) + float(sound.duration) and audio_handles.has(index):
			stage.audio.stop_event(audio_handles[index])
	if clock >= float(source.duration):
		active = false
		stage.audio.stop_events(self)
		player.velocity = Vector2.ZERO
		player.facing = 1.0
		var origin_offset := Vector2(
			-float(player.tuning.body_offset.x) * player.units,
			-player.body_size.y / 2.0 + float(player.tuning.body_offset.y) * player.units
		)
		player.checkpoint = Assets.vec(source.saved_spawn) - origin_offset
		player.checkpoint_facing = 1.0
		player.checkpoint_source = str(source.name)
		player.process_mode = Node.PROCESS_MODE_INHERIT
		finished.emit()


func _local_time(clip: Dictionary, time: float) -> float:
	# Hold the authored clip endpoint even if the source animation is longer
	# than the segment placed on this Timeline track.
	var elapsed := clampf(time - float(clip.start), 0.0, float(clip.duration))
	return clampf(elapsed * float(clip.speed) + float(clip.clip_in), 0.0, float(clip.length))


func _position(clip: Dictionary, time: float) -> Vector2:
	var local := _local_time(clip, time)
	var offset: Vector2 = (
		Vector2(
			sampler._sample(clip.axes[0], local) + float(clip.offset[0]) - float(clip.initial[0]),
			-(sampler._sample(clip.axes[1], local) + float(clip.offset[1]) - float(clip.initial[1]))
		)
		* player.units
	)
	var basis := Assets.matrix(clip.parent)
	return basis.basis_xform(offset)
