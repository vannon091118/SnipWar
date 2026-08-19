@tool
class_name SceneDirector
extends CanvasLayer

signal transition_started()
signal transition_midpoint()
signal transition_completed()

var _fade_rect: ColorRect
var _is_transitioning: bool = false

func _ready() -> void:
	layer = 95
	_build_ui()

func _build_ui() -> void:
	if _fade_rect != null:
		return
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeOverlay"
	_fade_rect.color = Color(0.02, 0.02, 0.04, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

func transition(duration: float = 0.4, on_midpoint: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	if _fade_rect == null:
		_build_ui()
	_is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_started.emit()

	var half := duration * 0.5
	var tw: Tween = create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		transition_midpoint.emit()
		if on_midpoint.is_valid():
			on_midpoint.call()
	)
	tw.tween_property(_fade_rect, "color:a", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
		transition_completed.emit()
	)

func is_transitioning() -> bool:
	return _is_transitioning
