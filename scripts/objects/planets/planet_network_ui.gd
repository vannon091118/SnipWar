class_name PlanetNetworkUI
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal amount_changed(value: float)
signal send_pressed

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ui_root: Control
var _tab_button: Button
var _panel: PanelContainer
var _selected_planet_label: Label
var _selected_count_label: Label
var _destination_option: OptionButton
var _count_labels: Dictionary = {}
var _amount_slider: HSlider
var _preview_label: Label
var _send_button: Button

func setup(planets: Array[Node2D], theme_config: UIThemeConfig = null) -> void:
	layer = 50
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_create_ui_root()
	_create_tab_button()
	_create_panel()
	var content := _create_panel_content()
	_create_header_labels(content)
	_create_destination_controls(content)
	_create_dispatch_controls(content)
	_create_units_list(content, planets)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
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
	_selected_count_label.text = "Einheiten: %d" % count

func update_count(planet: Node2D) -> void:
	if not _count_labels.has(planet):
		return
	var count_label: Label = _count_labels[planet]
	count_label.text = _count_text(planet)

func set_amount_bounds(bounds: Vector2i) -> void:
	_amount_slider.min_value = bounds.x
	_amount_slider.max_value = bounds.y
	_amount_slider.editable = bounds.y > 0
	if _amount_slider.value > bounds.y:
		_amount_slider.value = bounds.y
	_send_button.disabled = bounds.y <= 0

func reset_amount() -> void:
	_amount_slider.set_value_no_signal(1)

func selected_amount() -> int:
	return int(_amount_slider.value)

func has_selectable_amount() -> bool:
	return _amount_slider.editable

func set_preview(text: String) -> void:
	_preview_label.text = text

func is_panel_visible() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	_toggle_panel()

func get_panel() -> PanelContainer:
	return _panel

func index_of_destination(destination_name: String) -> int:
	for index in _destination_option.item_count:
		if _destination_option.get_item_text(index) == destination_name:
			return index
	return -1

func get_destination_option() -> OptionButton:
	return _destination_option

func get_amount_slider() -> HSlider:
	return _amount_slider

func get_preview_label() -> Label:
	return _preview_label

func get_send_button() -> Button:
	return _send_button

func get_count_label(planet: Node2D) -> Label:
	return _count_labels.get(planet) as Label

func _create_ui_root() -> void:
	_ui_root = Control.new()
	_ui_root.name = "PlanetTabUI"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

func _create_tab_button() -> void:
	_tab_button = Button.new()
	_tab_button.name = "PlanetTab"
	_tab_button.text = "PLANETEN"
	_tab_button.toggle_mode = true
	_tab_button.anchor_left = 1.0
	_tab_button.anchor_right = 1.0
	_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
	_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)
	_tab_button.pressed.connect(_toggle_panel)
	_ui_root.add_child(_tab_button)

func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PlanetPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.visible = false
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
	_ui_root.add_child(_panel)

func _create_panel_content() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _theme_config.content_margin_left)
	margin.add_theme_constant_override("margin_top", _theme_config.content_margin_top)
	margin.add_theme_constant_override("margin_right", _theme_config.content_margin_right)
	margin.add_theme_constant_override("margin_bottom", _theme_config.content_margin_bottom)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", _theme_config.content_separation)
	margin.add_child(content)
	return content

func _create_header_labels(content: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "PLANETENMENÜ"
	heading.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
	heading.add_theme_color_override("font_color", _theme_config.heading_text_color)
	content.add_child(heading)

	_selected_planet_label = Label.new()
	_selected_planet_label.text = "Kein Planet ausgewählt"
	_selected_planet_label.add_theme_color_override("font_color", _theme_config.selected_planet_text_color)
	content.add_child(_selected_planet_label)

	_selected_count_label = Label.new()
	_selected_count_label.text = "Einheiten: 0"
	_selected_count_label.add_theme_font_size_override("font_size", _theme_config.selected_count_font_size)
	_selected_count_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)
	content.add_child(_selected_count_label)

func _create_destination_controls(content: VBoxContainer) -> void:
	var destination_heading := Label.new()
	destination_heading.text = "Zielplanet"
	destination_heading.add_theme_color_override("font_color", _theme_config.secondary_text_color)
	content.add_child(destination_heading)

	_destination_option = OptionButton.new()
	_destination_option.name = "DestinationSelect"
	_destination_option.text = "Planet auswählen"
	_destination_option.disabled = true
	_destination_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination_option.item_selected.connect(_on_destination_selected)
	content.add_child(_destination_option)

func _create_dispatch_controls(content: VBoxContainer) -> void:
	var send_heading := Label.new()
	send_heading.text = "EINHEITEN SENDEN"
	send_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)
	content.add_child(send_heading)

	_amount_slider = HSlider.new()
	_amount_slider.name = "AmountSlider"
	_amount_slider.min_value = 1
	_amount_slider.max_value = 1
	_amount_slider.step = 1
	_amount_slider.value = 1
	_amount_slider.editable = false
	_amount_slider.value_changed.connect(_on_amount_changed)
	content.add_child(_amount_slider)

	_preview_label = Label.new()
	_preview_label.name = "PreviewLabel"
	_preview_label.text = "Keine Einheiten verfügbar"
	_preview_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)
	content.add_child(_preview_label)

	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.text = "SENDEN"
	_send_button.disabled = true
	_send_button.pressed.connect(_on_send_pressed)
	content.add_child(_send_button)

func _create_units_list(content: VBoxContainer, planets: Array[Node2D]) -> void:
	var separator := HSeparator.new()
	content.add_child(separator)

	var units_heading := Label.new()
	units_heading.text = "EINHEITEN PRO PLANET"
	units_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)
	content.add_child(units_heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var count_list := VBoxContainer.new()
	count_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_list.add_theme_constant_override("separation", _theme_config.list_separation)
	scroll.add_child(count_list)
	for planet in planets:
		var count_label := Label.new()
		count_label.text = _count_text(planet)
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_label.add_theme_color_override("font_color", _theme_config.accent_text_color)
		_count_labels[planet] = count_label
		count_list.add_child(count_label)

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
	_panel.visible = not _panel.visible
	_tab_button.set_pressed_no_signal(_panel.visible)
	panel_visibility_changed.emit(_panel.visible)

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()
