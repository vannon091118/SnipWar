class_name SimulationOverlay
extends CanvasLayer

## SimulationOverlay — Interaktives HUD-Overlay (Layer 60) für die Weltgeschichts-Simulation.
## Bietet Timeline-Scrubber, Transport-Controls (Play, Pause, 2x, 5x, Skip),
## Echtzeit-Event-Ticker und Wendepunkt-Hervorhebungen.

signal year_changed(current_year: int)
signal playback_finished()
signal turning_point_triggered(event: HistoryEvent)

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const TURNING_POINT_THRESHOLD: float = ImportanceEvaluator.THRESHOLD_TURNING_POINT

var _theme: UIThemeConfig = DEFAULT_THEME
var _events: Array[HistoryEvent] = []
var _eras: Array[Dictionary] = []

var _current_year: int = -300
var _target_year: int = 0
var _is_playing: bool = false
var _playback_speed: float = 1.0  # Jahre pro Sekunde (Basis 2 Jahre/s)
var _accumulator: float = 0.0

var _year_label: Label
var _era_badge: Label
var _play_pause_button: Button
var _speed_button: Button
var _slider: HSlider
var _ticker_container: VBoxContainer
var _turning_point_panel: PanelContainer
var _turning_point_label: Label
var _economy_container: VBoxContainer
var _economy_state: Dictionary = {}


func setup(events: Array[HistoryEvent], eras: Array[Dictionary], theme: UIThemeConfig = null) -> void:
	layer = 60
	_events = events
	_eras = eras
	_theme = theme if theme != null else DEFAULT_THEME
	_build_ui()
	set_year(-300)


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_accumulator += delta * _playback_speed * 4.0  # 4 Jahre pro Sekunde bei 1x
	if _accumulator >= 1.0:
		var years_to_advance: int = int(_accumulator)
		_accumulator -= float(years_to_advance)
		set_year(_current_year + years_to_advance)

		if _current_year >= _target_year:
			_is_playing = false
			_update_play_button()
			playback_finished.emit()


func set_year(year: int) -> void:
	_current_year = clampi(year, -300, 0)
	if _year_label != null:
		_year_label.text = "JAHR %d" % _current_year
	if _slider != null and not _slider.has_focus():
		_slider.value = _current_year

	_update_era_badge()
	_update_ticker_for_year(_current_year)
	year_changed.emit(_current_year)


func play() -> void:
	_is_playing = true
	_update_play_button()


func pause() -> void:
	_is_playing = false
	_update_play_button()


func toggle_play() -> void:
	_is_playing = not _is_playing
	_update_play_button()


func set_speed(speed: float) -> void:
	_playback_speed = speed
	if _speed_button != null:
		_speed_button.text = "%dx" % int(_playback_speed)


func skip_to_end() -> void:
	set_year(0)
	_is_playing = false
	_update_play_button()
	playback_finished.emit()


func _build_ui() -> void:
	# Haupt-Container am oberen Bildschirmrand
	var top_bar := MarginContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.add_theme_constant_override("margin_left", 24)
	top_bar.add_theme_constant_override("margin_top", 16)
	top_bar.add_theme_constant_override("margin_right", 24)
	add_child(top_bar)

	var panel := PanelContainer.new()
	panel.name = "ControlPanel"
	top_bar.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.name = "ControlsHBox"
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	# 1. Jahr & Epoche
	var title_vbox := VBoxContainer.new()
	title_vbox.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(title_vbox)

	_year_label = Label.new()
	_year_label.text = "JAHR -300"
	_year_label.add_theme_font_size_override("font_size", 20)
	_year_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	title_vbox.add_child(_year_label)

	_era_badge = Label.new()
	_era_badge.text = "Die Ära der Ersten"
	_era_badge.add_theme_font_size_override("font_size", 12)
	_era_badge.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	title_vbox.add_child(_era_badge)

	# 2. Transport Buttons
	_play_pause_button = Button.new()
	_play_pause_button.text = "▶ PLAY"
	_play_pause_button.custom_minimum_size = Vector2(90, 36)
	_play_pause_button.pressed.connect(toggle_play)
	hbox.add_child(_play_pause_button)

	_speed_button = Button.new()
	_speed_button.text = "1x"
	_speed_button.custom_minimum_size = Vector2(50, 36)
	_speed_button.pressed.connect(_on_speed_toggle)
	hbox.add_child(_speed_button)

	var skip_btn := Button.new()
	skip_btn.text = "⏭ ENDE"
	skip_btn.custom_minimum_size = Vector2(80, 36)
	skip_btn.pressed.connect(skip_to_end)
	hbox.add_child(skip_btn)

	# 3. Timeline Slider
	_slider = HSlider.new()
	_slider.min_value = -300
	_slider.max_value = 0
	_slider.value = -300
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(v): set_year(int(v)))
	hbox.add_child(_slider)

	# 4. Event Ticker rechts unten
	var ticker_margin := MarginContainer.new()
	ticker_margin.name = "TickerMargin"
	ticker_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ticker_margin.add_theme_constant_override("margin_right", 24)
	ticker_margin.add_theme_constant_override("margin_bottom", 24)
	add_child(ticker_margin)

	_ticker_container = VBoxContainer.new()
	_ticker_container.name = "TickerFeed"
	_ticker_container.custom_minimum_size = Vector2(380, 0)
	_ticker_container.add_theme_constant_override("separation", 6)
	ticker_margin.add_child(_ticker_container)

	# 5. Wendepunkt Banner
	_turning_point_panel = PanelContainer.new()
	_turning_point_panel.name = "TurningPointBanner"
	_turning_point_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_turning_point_panel.position = Vector2(0, 100)
	_turning_point_panel.visible = false
	add_child(_turning_point_panel)

	_turning_point_label = Label.new()
	_turning_point_label.name = "TurningPointLabel"
	_turning_point_label.add_theme_font_size_override("font_size", 16)
	_turning_point_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	_turning_point_panel.add_child(_turning_point_label)

	_economy_container = VBoxContainer.new()
	_economy_container.name = "EconomySummary"
	_economy_container.custom_minimum_size = Vector2(210, 0)
	top_bar.add_child(_economy_container)


func set_economy_state(economy_state: Dictionary) -> void:
	_economy_state = economy_state.duplicate(true)
	if _economy_container == null:
		return
	for child in _economy_container.get_children():
		child.queue_free()
	for fid in _economy_state:
		var data: Dictionary = _economy_state[fid]
		var line := Label.new()
		line.text = "%s  Lager %.0f  %+0.0f/J" % [String(fid).to_upper(), float(data.get("stock", 0.0)), float(data.get("net", 0.0))]
		line.add_theme_font_size_override("font_size", 11)
		_economy_container.add_child(line)


func _update_play_button() -> void:
	if _play_pause_button != null:
		_play_pause_button.text = "⏸ PAUSE" if _is_playing else "▶ PLAY"


func _on_speed_toggle() -> void:
	if _playback_speed == 1.0:
		set_speed(2.0)
	elif _playback_speed == 2.0:
		set_speed(5.0)
	else:
		set_speed(1.0)


func _update_era_badge() -> void:
	if _era_badge == null or _eras.is_empty():
		return
	for era in _eras:
		var sy: int = int(era.get("start_year", -300))
		var ey: int = int(era.get("end_year", 0))
		if _current_year >= sy and _current_year <= ey:
			_era_badge.text = str(era.get("name", ""))
			break


func _update_ticker_for_year(year: int) -> void:
	if _ticker_container == null:
		return
	# Suche Events aus diesem Jahr
	for ev in _events:
		if ev.year == year and ev.importance >= 0.45:
			_push_ticker_item(ev)
			if ev.importance >= TURNING_POINT_THRESHOLD:
				_show_turning_point_flash(ev)


func _push_ticker_item(event: HistoryEvent) -> void:
	var item := Label.new()
	item.text = "[%d] %s: %s" % [event.year, String(event.event_type).to_upper(), event.trigger]
	item.add_theme_font_size_override("font_size", 13)

	if event.event_type in [&"war_declared", &"conquest", &"defeat"]:
		item.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	elif event.event_type in [&"alliance", &"trade"]:
		item.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		item.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

	_ticker_container.add_child(item)

	# Halte maximal 5 Einträge im Ticker
	if _ticker_container.get_child_count() > 5:
		var oldest: Node = _ticker_container.get_child(0)
		_ticker_container.remove_child(oldest)
		oldest.queue_free()


func _show_turning_point_flash(event: HistoryEvent) -> void:
	if _turning_point_panel == null or _turning_point_label == null:
		return
	_turning_point_label.text = "⚡ HISTORISCHER WENDEPUNKT (%d): %s" % [event.year, event.trigger]
	_turning_point_panel.visible = true
	turning_point_triggered.emit(event)

	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			var timer := tree.create_timer(2.0)
			timer.timeout.connect(func(): if _turning_point_panel != null: _turning_point_panel.visible = false)
