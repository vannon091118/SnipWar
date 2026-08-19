class_name PlanetNetworkUI
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal amount_changed(value: float)
signal send_pressed

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _count_labels: Dictionary = {}

@onready var _ui_root: Control = get_node_or_null("PlanetTabUI")
@onready var _tab_button: Button = get_node_or_null("PlanetTabUI/PlanetTab")
@onready var _panel: PanelContainer = get_node_or_null("PlanetTabUI/PlanetPanel")
@onready var _heading_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/HeadingLabel")
@onready var _selected_planet_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedPlanetLabel")
@onready var _selected_count_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedCountLabel")
@onready var _destination_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationHeading")
@onready var _destination_option: OptionButton = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationSelect")
@onready var _send_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendHeading")
@onready var _amount_slider: HSlider = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/AmountSlider")
@onready var _preview_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/PreviewLabel")
@onready var _send_button: Button = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendButton")
@onready var _units_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UnitsHeading")
@onready var _count_list: VBoxContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ScrollContainer/CountList")
@onready var _margin: MarginContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer")
@onready var _content: VBoxContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content")

func setup(planets: Array[Node2D], theme_config: UIThemeConfig = null) -> void:
	layer = 50
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ensure_node_references()
	_apply_theme()
	_connect_internal_signals()
	_populate_units_list(planets)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()

func _ensure_node_references() -> void:
	if _ui_root == null:
		_ui_root = get_node_or_null("PlanetTabUI")
	if _tab_button == null:
		_tab_button = get_node_or_null("PlanetTabUI/PlanetTab")
	if _panel == null:
		_panel = get_node_or_null("PlanetTabUI/PlanetPanel")
	if _heading_label == null:
		_heading_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/HeadingLabel")
	if _selected_planet_label == null:
		_selected_planet_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedPlanetLabel")
	if _selected_count_label == null:
		_selected_count_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedCountLabel")
	if _destination_heading == null:
		_destination_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationHeading")
	if _destination_option == null:
		_destination_option = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationSelect")
	if _send_heading == null:
		_send_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendHeading")
	if _amount_slider == null:
		_amount_slider = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/AmountSlider")
	if _preview_label == null:
		_preview_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/PreviewLabel")
	if _send_button == null:
		_send_button = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendButton")
	if _units_heading == null:
		_units_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UnitsHeading")
	if _count_list == null:
		_count_list = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ScrollContainer/CountList")
	if _margin == null:
		_margin = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer")
	if _content == null:
		_content = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content")

func _apply_theme() -> void:
	if _tab_button != null:
		_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
		_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)

	if _panel != null:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = _theme_config.panel_background
		panel_style.border_color = _theme_config.panel_border
		panel_style.border_width_left = _theme_config.panel_border_width
		panel_style.border_width_top = _theme_config.panel_border_width
		panel_style.border_width_right = _theme_config.panel_border_width
		panel_style.border_width_bottom = _theme_config.panel_border_width
		panel_style.corner_radius_top_left = _theme_config.panel_corner_radius
		panel_style.corner_radius_top_right = _theme_config.panel_corner_radius
		panel_style.corner_radius_bottom_left = _theme_config.panel_corner_radius
		panel_style.corner_radius_bottom_right = _theme_config.panel_corner_radius
		_panel.add_theme_stylebox_override("panel", panel_style)

	if _margin != null:
		_margin.add_theme_constant_override("margin_left", _theme_config.content_margin_left)
		_margin.add_theme_constant_override("margin_top", _theme_config.content_margin_top)
		_margin.add_theme_constant_override("margin_right", _theme_config.content_margin_right)
		_margin.add_theme_constant_override("margin_bottom", _theme_config.content_margin_bottom)

	if _content != null:
		_content.add_theme_constant_override("separation", _theme_config.content_separation)

	if _heading_label != null:
		_heading_label.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
		_heading_label.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _selected_planet_label != null:
		_selected_planet_label.add_theme_color_override("font_color", _theme_config.selected_planet_text_color)

	if _selected_count_label != null:
		_selected_count_label.add_theme_font_size_override("font_size", _theme_config.selected_count_font_size)
		_selected_count_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)

	if _destination_heading != null:
		_destination_heading.add_theme_color_override("font_color", _theme_config.secondary_text_color)

	if _send_heading != null:
		_send_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _preview_label != null:
		_preview_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)

	if _units_heading != null:
		_units_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _count_list != null:
		_count_list.add_theme_constant_override("separation", _theme_config.list_separation)

func _connect_internal_signals() -> void:
	if _tab_button != null and not _tab_button.pressed.is_connected(_toggle_panel):
		_tab_button.pressed.connect(_toggle_panel)
	if _destination_option != null and not _destination_option.item_selected.is_connected(_on_destination_selected):
		_destination_option.item_selected.connect(_on_destination_selected)
	if _amount_slider != null and not _amount_slider.value_changed.is_connected(_on_amount_changed):
		_amount_slider.value_changed.connect(_on_amount_changed)
	if _send_button != null and not _send_button.pressed.is_connected(_on_send_pressed):
		_send_button.pressed.connect(_on_send_pressed)

func _populate_units_list(planets: Array[Node2D]) -> void:
	if _count_list == null:
		return
	for child in _count_list.get_children():
		child.queue_free()
	_count_labels.clear()

	for planet in planets:
		var count_label := Label.new()
		count_label.text = _count_text(planet)
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_label.add_theme_color_override("font_color", _theme_config.accent_text_color)
		_count_labels[planet] = count_label
		_count_list.add_child(count_label)

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	_ensure_node_references()
	_panel.visible = true
	_tab_button.set_pressed_no_signal(true)
	_selected_planet_label.text = "Planet: %s" % planet.name
	_destination_option.clear()
	_destination_option.disabled = destinations.is_empty()
	for destination in destinations:
		_destination_option.add_item(destination.name)
	if default_destination != null:
		for index in _destination_option.item_count:
			if _destination_option.get_item_text(index) == default_destination.name:
				_destination_option.select(index)
				break

func set_selected_count(count: int) -> void:
	_ensure_node_references()
	_selected_count_label.text = "Einheiten: %d" % count

func update_count(planet: Node2D) -> void:
	if not _count_labels.has(planet):
		return
	var count_label: Label = _count_labels[planet]
	count_label.text = _count_text(planet)

func set_amount_bounds(bounds: Vector2i) -> void:
	_ensure_node_references()
	_amount_slider.min_value = bounds.x
	_amount_slider.max_value = bounds.y
	_amount_slider.editable = bounds.y > 0
	if _amount_slider.value > bounds.y:
		_amount_slider.value = bounds.y
	_send_button.disabled = bounds.y <= 0

func reset_amount() -> void:
	_ensure_node_references()
	_amount_slider.set_value_no_signal(1)

func selected_amount() -> int:
	_ensure_node_references()
	return int(_amount_slider.value)

func has_selectable_amount() -> bool:
	_ensure_node_references()
	return _amount_slider.editable

func set_preview(text: String) -> void:
	_ensure_node_references()
	_preview_label.text = text

func is_panel_visible() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	_toggle_panel()

func get_panel() -> PanelContainer:
	_ensure_node_references()
	return _panel

func index_of_destination(destination_name: String) -> int:
	_ensure_node_references()
	for index in _destination_option.item_count:
		if _destination_option.get_item_text(index) == destination_name:
			return index
	return -1

func get_destination_option() -> OptionButton:
	_ensure_node_references()
	return _destination_option

func get_amount_slider() -> HSlider:
	_ensure_node_references()
	return _amount_slider

func get_preview_label() -> Label:
	_ensure_node_references()
	return _preview_label

func get_send_button() -> Button:
	_ensure_node_references()
	return _send_button

func get_count_label(planet: Node2D) -> Label:
	return _count_labels.get(planet) as Label

func _count_text(planet: Node2D) -> String:
	return "%s: %d" % [planet.name, int(planet.get("worker_count"))]

func _apply_responsive_layout() -> void:
	if not is_instance_valid(_tab_button) or not is_instance_valid(_panel):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var panel_width := clampf(
		viewport_size.x * _theme_config.panel_width_ratio,
		_theme_config.panel_min_width,
		_theme_config.panel_max_width
	)
	_tab_button.offset_left = -panel_width
	_tab_button.offset_top = _theme_config.edge_margin
	_tab_button.offset_right = -_theme_config.edge_margin
	_tab_button.offset_bottom = _theme_config.edge_margin + _theme_config.tab_height
	_panel.offset_left = -panel_width
	_panel.offset_top = _theme_config.edge_margin + _theme_config.tab_height + _theme_config.panel_gap
	_panel.offset_right = -_theme_config.edge_margin
	_panel.offset_bottom = -_theme_config.edge_margin

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()

func _toggle_panel() -> void:
	_ensure_node_references()
	_panel.visible = not _panel.visible
	_tab_button.set_pressed_no_signal(_panel.visible)
	panel_visibility_changed.emit(_panel.visible)

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()
