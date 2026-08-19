class_name PlanetNetworkUI
extends CanvasLayer

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal amount_changed(value: float)
signal send_pressed

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

func setup(planets: Array[Node2D]) -> void:
	layer = 50
	_create_ui_root()
	_create_tab_button()
	_create_panel()
	var content := _create_panel_content()
	_create_header_labels(content)
	_create_destination_controls(content)
	_create_dispatch_controls(content)
	_create_units_list(content, planets)

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

func index_of_destination(name: String) -> int:
	for index in _destination_option.item_count:
		if _destination_option.get_item_text(index) == name:
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
	_tab_button.offset_left = -300.0
	_tab_button.offset_top = 16.0
	_tab_button.offset_right = -16.0
	_tab_button.offset_bottom = 52.0
	_tab_button.add_theme_font_size_override("font_size", 16)
	_tab_button.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_tab_button.pressed.connect(_toggle_panel)
	_ui_root.add_child(_tab_button)

func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PlanetPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -300.0
	_panel.offset_top = 58.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -16.0
	_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.10, 0.94)
	panel_style.border_color = Color(0.25, 0.82, 0.98, 0.88)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	_ui_root.add_child(_panel)

func _create_panel_content() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return content

func _create_header_labels(content: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "PLANETENMENÜ"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(0.97, 0.78, 0.35, 1.0))
	content.add_child(heading)

	_selected_planet_label = Label.new()
	_selected_planet_label.text = "Kein Planet ausgewählt"
	_selected_planet_label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.98, 1.0))
	content.add_child(_selected_planet_label)

	_selected_count_label = Label.new()
	_selected_count_label.text = "Einheiten: 0"
	_selected_count_label.add_theme_font_size_override("font_size", 16)
	_selected_count_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.70, 1.0))
	content.add_child(_selected_count_label)

func _create_destination_controls(content: VBoxContainer) -> void:
	var destination_heading := Label.new()
	destination_heading.text = "Zielplanet"
	destination_heading.add_theme_color_override("font_color", Color(0.68, 0.82, 0.92, 1.0))
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
	send_heading.add_theme_color_override("font_color", Color(0.97, 0.78, 0.35, 1.0))
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
	_preview_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.70, 1.0))
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
	units_heading.add_theme_color_override("font_color", Color(0.97, 0.78, 0.35, 1.0))
	content.add_child(units_heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var count_list := VBoxContainer.new()
	count_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_list.add_theme_constant_override("separation", 4)
	scroll.add_child(count_list)
	for planet in planets:
		var count_label := Label.new()
		count_label.text = _count_text(planet)
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_label.add_theme_color_override("font_color", Color(0.80, 0.87, 0.94, 1.0))
		_count_labels[planet] = count_label
		count_list.add_child(count_label)

func _count_text(planet: Node2D) -> String:
	return "%s: %d" % [planet.name, int(planet.get("worker_count"))]

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
