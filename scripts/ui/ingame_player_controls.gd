@tool
class_name IngamePlayerControls
extends PanelContainer

signal play_toggled(is_playing: bool)
signal seek_requested(time_seconds: float)
signal speed_changed(multiplier: float)
signal skip_pressed()

var is_playing: bool = true
var total_duration: float = 10.0
var current_time: float = 0.0
var playback_speed: float = 1.0

var _play_button: Button
var _scrubber: HSlider
var _time_label: Label
var _speed_button: Button
var _skip_button: Button
var _is_user_scrubbing: bool = false

var _speed_options: Array[float] = [0.5, 1.0, 2.0, 4.0]
var _speed_index: int = 1

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _play_button != null:
		return

	custom_minimum_size = Vector2(560.0, 44.0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	_play_button = Button.new()
	_play_button.name = "PlayButton"
	_play_button.text = "❚❚"
	_play_button.custom_minimum_size = Vector2(36.0, 28.0)
	_play_button.pressed.connect(_on_play_pressed)
	hbox.add_child(_play_button)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "00:00 / 00:10"
	_time_label.custom_minimum_size = Vector2(90.0, 20.0)
	_time_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(_time_label)

	_scrubber = HSlider.new()
	_scrubber.name = "Scrubber"
	_scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrubber.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrubber.min_value = 0.0
	_scrubber.max_value = 10.0
	_scrubber.step = 0.05
	_scrubber.value = 0.0
	_scrubber.drag_started.connect(func(): _is_user_scrubbing = true)
	_scrubber.drag_ended.connect(_on_scrub_ended)
	hbox.add_child(_scrubber)

	_speed_button = Button.new()
	_speed_button.name = "SpeedButton"
	_speed_button.text = "1.0x"
	_speed_button.custom_minimum_size = Vector2(48.0, 28.0)
	_speed_button.pressed.connect(_on_speed_pressed)
	hbox.add_child(_speed_button)

	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "SKIP ▶▶"
	_skip_button.custom_minimum_size = Vector2(64.0, 28.0)
	_skip_button.pressed.connect(func(): skip_pressed.emit())
	hbox.add_child(_skip_button)

func setup(duration: float) -> void:
	_build_ui()
	total_duration = maxf(duration, 0.1)
	current_time = 0.0
	is_playing = true
	_scrubber.max_value = total_duration
	_scrubber.value = 0.0
	_play_button.text = "❚❚"
	_update_time_display()

func set_progress(time: float) -> void:
	current_time = clampf(time, 0.0, total_duration)
	if not _is_user_scrubbing and _scrubber != null:
		_scrubber.value = current_time
	_update_time_display()

func _update_time_display() -> void:
	if _time_label != null:
		var cur_m := int(current_time / 60.0)
		var cur_s := int(current_time) % 60
		var tot_m := int(total_duration / 60.0)
		var tot_s := int(total_duration) % 60
		_time_label.text = "%02d:%02d / %02d:%02d" % [cur_m, cur_s, tot_m, tot_s]

func _on_play_pressed() -> void:
	is_playing = not is_playing
	_play_button.text = "❚❚" if is_playing else "▶"
	play_toggled.emit(is_playing)

func _on_scrub_ended(value_changed: bool) -> void:
	_is_user_scrubbing = false
	if value_changed:
		current_time = _scrubber.value
		seek_requested.emit(current_time)

func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % _speed_options.size()
	playback_speed = _speed_options[_speed_index]
	_speed_button.text = "%.1fx" % playback_speed
	speed_changed.emit(playback_speed)
