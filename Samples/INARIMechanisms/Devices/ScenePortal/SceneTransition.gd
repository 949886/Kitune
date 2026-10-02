extends CanvasLayer
## Optional, persistent host coordinator. It never loads arbitrary paths or
## mutates an actor: the host swaps its scene only after covered, then supplies
## the matching ticket to finish_load. Tickets reject stale asynchronous work.
signal began(actor: Node2D, request: Dictionary, ticket: int)
signal covered(request: Dictionary, ticket: int)
signal loaded(request: Dictionary, ticket: int)
signal finished(request: Dictionary, ticket: int)
signal cancelled(request: Dictionary, ticket: int)
const Configuration = preload("TransitionSettings.gd")
enum Phase { IDLE, FADING_OUT, COVERED, FADING_IN }
@export var settings: Configuration = preload("TransitionSettings.tres")
var phase := Phase.IDLE
var ticket := 0
var payload: Dictionary = {}
var cover: ColorRect
var fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cover = ColorRect.new()
	cover.color = settings.cover_color
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.hide()
	cover.modulate.a = 0


## Source IsLoadingScene ends before fade-in. A fresh exit during fade-in may
## replace that visual transition; it must not run two competing fade tweens.
func is_loading() -> bool:
	return phase == Phase.FADING_OUT or phase == Phase.COVERED


func is_transitioning() -> bool:
	return phase != Phase.IDLE


func request(actor: Node2D, data: Dictionary) -> int:
	if is_loading() or not is_instance_valid(actor) or str(data.get("destination", "")).is_empty():
		return 0
	var previous_alpha := cover.modulate.a
	if phase == Phase.FADING_IN:
		cancel()
		if phase != Phase.IDLE:
			return 0
	ticket += 1
	var current := ticket
	payload = data.duplicate(true)
	phase = Phase.FADING_OUT
	cover.show()
	cover.modulate.a = previous_alpha
	began.emit(actor, payload.duplicate(true), current)
	if ticket == current and phase == Phase.FADING_OUT:
		_fade_to(1.0, _covered.bind(current))
	return current


func _fade_to(alpha: float, completed: Callable) -> void:
	if fade != null:
		fade.kill()
	# DOTween SetUpdate(isIndependentUpdate:true): fade survives a paused tree
	# and Engine.time_scale = 0. Gameplay clocks remain entirely host-owned.
	fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_property(cover, "modulate:a", alpha, settings.fade_seconds)
	fade.finished.connect(completed)


func _covered(current: int) -> void:
	if ticket != current or phase != Phase.FADING_OUT:
		return
	phase = Phase.COVERED
	covered.emit(payload.duplicate(true), current)


func finish_load(current: int) -> bool:
	if ticket != current or phase != Phase.COVERED:
		return false
	phase = Phase.FADING_IN
	loaded.emit(payload.duplicate(true), current)
	if ticket == current and phase == Phase.FADING_IN:
		_fade_to(0.0, _finished.bind(current))
	return true


func _finished(current: int) -> void:
	if ticket != current or phase != Phase.FADING_IN:
		return
	var completed := payload.duplicate(true)
	phase = Phase.IDLE
	payload.clear()
	cover.hide()
	finished.emit(completed, current)


func cancel() -> void:
	if phase == Phase.IDLE:
		return
	var abandoned := payload.duplicate(true)
	var current := ticket
	phase = Phase.IDLE
	payload.clear()
	if fade != null:
		fade.kill()
	cover.hide()
	cover.modulate.a = 0
	cancelled.emit(abandoned, current)


func _exit_tree() -> void:
	# A persistent host can restore input on cancellation even when the gallery
	# removes this coordinator halfway through a transition.
	cancel()
