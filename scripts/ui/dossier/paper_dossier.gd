class_name PaperDossier
extends CanvasLayer

## Full-screen "paper dossier" modal: dims and freezes the world, folds in a
## slightly rotated paper sheet with a scale/fade tween, and hosts one view.
## Layer 80 sits above the HUD (50), TechnologyMenu (60) and PauseMenu (70),
## but below CaptureDecisionOverlay (90) and the grain overlay (100).

signal opened()
signal closed()

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _open := false
var _tween: Tween
var _dim: ColorRect
var _sheet: PanelContainer
var _title_label: Label
var _close_button: Button
var _content_host: Control

func setup(theme_config: UIThemeConfig = null) -> void:
	layer = 80
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_build_ui()
	_set_open(false, false)
	get_viewport().size_changed.connect(_apply_sheet_layout)

func is_open() -> bool:
	return _open

func open_view(content: Control, title: String) -> void:
	_replace_content(content)
	if _title_label != null:
		_title_label.text = title
	_apply_sheet_layout()
	_set_open(true, true)

func close() -> void:
	if _open:
		_set_open(false, true)

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.03, 0.05, 0.68)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.visible = false
	_sheet.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.texture_style_box(
			_theme_config,
			_theme_config.modal_background_texture,
			_theme_config.panel_background,
			float(_theme_config.card_padding)
		)
	)
	add_child(_sheet)

	var margin := MarginContainer.new()
	margin.name = "SheetMargin"
	margin.add_theme_constant_override("margin_left", _theme_config.content_margin_left)
	margin.add_theme_constant_override("margin_top", _theme_config.content_margin_top)
	margin.add_theme_constant_override("margin_right", _theme_config.content_margin_right)
	margin.add_theme_constant_override("margin_bottom", _theme_config.content_margin_bottom)
	_sheet.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "SheetColumn"
	column.add_theme_constant_override("separation", _theme_config.content_separation)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "SheetHeader"
	header.add_theme_constant_override("separation", _theme_config.card_padding)
	column.add_child(header)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "DOSSIER"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", _theme_config.panel_title_font_size)
	_title_label.add_theme_color_override("font_color", _theme_config.heading_text_color)
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "✕  SCHLIESSEN"
	_close_button.focus_mode = Control.FOCUS_NONE
	UIBaseUtils.apply_button_theme(_close_button, _theme_config)
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	column.add_child(UIBaseUtils.make_separator())

	_content_host = Control.new()
	_content_host.name = "ContentHost"
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_content_host)

func _replace_content(content: Control) -> void:
	if _content_host == null:
		return
	for child in _content_host.get_children():
		_content_host.remove_child(child)
		child.queue_free()
	if content != null:
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content_host.add_child(content)

func _apply_sheet_layout() -> void:
	if not is_instance_valid(_sheet):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var sheet_size := Vector2(viewport_size.x * 0.92, viewport_size.y * 0.86)
	_sheet.position = (viewport_size - sheet_size) * 0.5
	_sheet.size = sheet_size
	_sheet.pivot_offset = sheet_size * 0.5
	_sheet.rotation = deg_to_rad(-1.1)

func _set_open(open_value: bool, animate: bool) -> void:
	_open = open_value
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if is_instance_valid(_dim):
		_dim.visible = open_value
	if not is_instance_valid(_sheet):
		return
	_sheet.visible = open_value
	if open_value:
		if animate:
			_sheet.modulate.a = 0.0
			_sheet.scale = Vector2(0.95, 0.95)
			_tween = create_tween().set_parallel(true)
			_tween.tween_property(_sheet, "modulate:a", 1.0, _theme_config.transition_duration)
			_tween.tween_property(_sheet, "scale", Vector2.ONE, _theme_config.transition_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_sheet.modulate.a = 1.0
			_sheet.scale = Vector2.ONE
		opened.emit()
	else:
		_sheet.modulate.a = 1.0
		_sheet.scale = Vector2.ONE
		closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
