class_name MessageFeed
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _list: VBoxContainer
var _event_log: Node

func setup(event_log: Node, theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_event_log = event_log
	_list = get_node_or_null("FeedRoot/ToastList") as VBoxContainer
	if _event_log != null and _event_log.has_signal("message_pushed") and not _event_log.message_pushed.is_connected(_on_message_pushed):
		_event_log.message_pushed.connect(_on_message_pushed)
	if _event_log != null and _event_log.has_method("set_max_entries"):
		_event_log.set_max_entries(_theme_config.message_max_log_entries)
	_replay_visible_history()

func _replay_visible_history() -> void:
	if _list == null or _event_log == null or not _event_log.has_method("get_entries"):
		return
	for entry in _event_log.get_entries():
		if bool(entry.get("visible", false)):
			_add_toast(entry.get("category", &""), String(entry.get("text", "")))

func _on_message_pushed(category: StringName, text: String) -> void:
	_add_toast(category, text)

func _add_toast(category: StringName, text: String) -> void:
	if _list == null or text.is_empty():
		return
	var toast := PanelContainer.new()
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.add_theme_stylebox_override("panel", _theme_config.make_style_box(_theme_config.card_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", _message_color(category))
	label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
	toast.add_child(label)
	_list.add_child(toast)
	while _list.get_child_count() > _theme_config.message_max_visible_toasts:
		var oldest: Node = _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
	var tween := create_tween()
	tween.tween_interval(_theme_config.message_toast_duration)
	tween.tween_property(toast, "modulate:a", 0.0, _theme_config.message_toast_fade_duration)
	tween.tween_callback(Callable(toast, "queue_free"))

func _message_color(category: StringName) -> Color:
	match category:
		&"military":
			return _theme_config.branch_military_color
		&"tech":
			return _theme_config.branch_tech_color
		&"economy":
			return _theme_config.branch_economy_color
		&"discovery":
			return _theme_config.accent_text_color
		_:
			return _theme_config.heading_text_color
