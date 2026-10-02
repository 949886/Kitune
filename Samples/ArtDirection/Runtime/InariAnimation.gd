extends Sprite2D
## Sprite keys retain the original clip timestamps and trimmed-sprite pivots.

const Assets = preload("res://Samples/ArtDirection/Runtime/OriginalAssets.gd")
const MaterialSettings = preload("res://Samples/ArtDirection/Runtime/OriginalMaterial.gd")
const GlowShader = preload("res://Samples/ArtDirection/Shaders/OriginalGlow.gdshader")
const Appearance = preload("res://Samples/ArtDirection/Runtime/InariAppearance.gd")

@export_file("*.json") var appearance_path := ""

var clips: Dictionary
var clip_name := ""
var elapsed := 0.0
var facing := 1.0
var pose_offset := Vector2.ZERO
var gfx_rotation := 0.0
var body_rotation := 0.0
var body_origin := Vector2.ZERO
var renderer: Dictionary
var appearance := Appearance.new()
var wall_origin := Vector2.ZERO
var ceiling_origin := Vector2.ZERO


func _ready() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clips = Assets.read_json(Assets.ROOT + "player.json")
	renderer = Assets.read_json(Assets.ROOT + "player_rendering.json")
	appearance.configure(appearance_path)
	modulate = Assets.color(renderer.color)
	apply_material(self)
	play("idle")


func set_appearance(path: String) -> void:
	appearance_path = path
	appearance.configure(path)
	# Sample the current pose immediately, including frozen reference views.
	# Do not restart the clip: its clock also drives hit and sound events.
	_refresh_frame()


func apply_material(visual: Sprite2D, lighting: Node = null) -> void:
	# Standalone controller probes have no source scene lighting. Real levels
	# replace this surface shader with the layer's native URP lighting variant.
	var surface := ShaderMaterial.new()
	surface.shader = GlowShader
	MaterialSettings.configure(surface, renderer.material, visual.get_viewport().use_hdr_2d)
	visual.material = surface
	if is_instance_valid(lighting):
		lighting.apply_source(visual, renderer.material, int(renderer.layer_id), "player")
		# Native Awake instantiates this material. Buff/outline changes must not
		# mutate the shared layer variant or another camera's independent copy.
		visual.material = visual.material.duplicate()


func play(next: String, restart := false) -> void:
	if clip_name == next and not restart:
		return

	assert(clips.has(next), "Missing original INARI clip: " + next)
	clip_name = next
	elapsed = 0.0
	_refresh_frame()


func advance(delta: float) -> void:
	if clips[clip_name].get("clock", "") == "timeline_loop":
		# SpriteTrackMixerBehaviour samples its unwrapped float clock first.
		_refresh_frame()
		elapsed = PackedFloat32Array([elapsed + PackedFloat32Array([delta])[0]])[0]
		return
	elapsed += delta * float(clips[clip_name].get("speed", 1.0))
	_refresh_frame()


func finished() -> bool:
	return not bool(clips[clip_name].loop) and elapsed >= float(clips[clip_name].length)


func _refresh_frame() -> void:
	var clip: Dictionary = clips[clip_name]
	if clip.frames.is_empty():
		return

	var time := minf(elapsed, float(clip.length))
	if clip.loop:
		time = fmod(elapsed, float(clip.length))
	if not appearance.profile.is_empty():
		_refresh_appearance_frame(appearance.sample(clip_name, clip, time))
		return

	var key: String = clip.frames[0][1]
	if clip.get("clock", "") == "timeline_loop":
		var index := maxi(0, floori(PackedFloat32Array([elapsed * clip.frame_rate])[0]))
		key = clip.frames[index % clip.frames.size()][1]
	else:
		for frame: Array in clip.frames:
			if float(frame[0]) > time:
				break
			key = frame[1]

	var info := Assets.sprite_info(key)
	texture = Assets.texture(key)
	# Unity rotates the GFX parent, so a trimmed frame's pivot offset rotates
	# with its pixels. Rotating only Sprite2D would make wide attack frames orbit.
	var offset := Vector2(Assets.vec(info.offset).x * facing, Assets.vec(info.offset).y)
	position = (
		body_origin
		+ (pose_offset - body_origin).rotated(body_rotation)
		+ offset.rotated(body_rotation + gfx_rotation)
	)
	rotation = body_rotation + gfx_rotation
	# Replacement drawings use their own display scale on both axes. Restore
	# the complete source scale when switching back, even during a rotated pose.
	scale = Vector2(facing, 1.0)


func _refresh_appearance_frame(frame: Dictionary) -> void:
	texture = frame.texture
	var pixel_scale := float(frame.scale)
	var anchor: Vector2 = frame.anchor
	var mirror := Vector2(facing, 1.0)
	scale = mirror * pixel_scale
	rotation = body_rotation + gfx_rotation
	if frame.attachment == "ceiling":
		# These drawings already show arms overhead. The original controller
		# rotates its collision box for roof traversal; rotating this artwork a
		# second time would make her hang sideways. Attach her hands to the roof.
		rotation = gfx_rotation
		position = ceiling_origin + (-anchor * pixel_scale * mirror).rotated(rotation)
		return
	var attachment := wall_origin if frame.attachment == "wall" else Vector2.ZERO
	var offset := (attachment - pose_offset - anchor * pixel_scale) * mirror
	# Convert from a foot/hand anchor back to the source GFX pivot so directed
	# weak-point dashes still rotate about the body rather than an atlas corner.
	position = (
		body_origin
		+ (pose_offset - body_origin).rotated(body_rotation)
		+ offset.rotated(rotation)
	)
