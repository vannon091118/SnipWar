extends Node2D

var _planets: Array[Node2D] = []
var _routes: Dictionary = {}
var _active_planet: Node2D
var _ui_layer: CanvasLayer
var _ui_root: Control
var _tab_button: Button
var _panel: PanelContainer
var _selected_planet_label: Label
var _selected_count_label: Label
var _destination_option: OptionButton
var _destination_planets: Array[Node2D] = []
var _count_labels: Dictionary = {}
var _line_phase := 0.0

func _ready() -> void:
	for child in get_parent().get_children():
		if child is Node2D and child.get("layout_size") != null:
			_planets.append(child)
			child.planet_selected.connect(_on_planet_selected)
			child.worker_count_changed.connect(_on_worker_count_changed)
	_create_ui.call_deferred()

func _create_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "PlanetTabLayer"
	_ui_layer.layer = 50
	add_child(_ui_layer)

	_ui_root = Control.new()
	_ui_root.name = "PlanetTabUI"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)

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

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

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
	for planet in _planets:
		var count_label := Label.new()
		count_label.text = _count_text(planet)
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_label.add_theme_color_override("font_color", Color(0.80, 0.87, 0.94, 1.0))
		_count_labels[planet] = count_label
		count_list.add_child(count_label)

func _process(delta: float) -> void:
	if _active_planet != null and is_instance_valid(_panel) and _panel.visible:
		_line_phase += delta
		queue_redraw()

func _draw() -> void:
	if _active_planet == null or not is_instance_valid(_panel) or not _panel.visible:
		return
	var neighbors := get_neighbors(_active_planet)
	for index in neighbors.size():
		var pulse := 0.5 + sin(_line_phase * 2.0 + float(index)) * 0.18
		var color := Color(0.25, 0.85, 1.0, pulse)
		draw_line(to_local(_active_planet.global_position), to_local(neighbors[index].global_position), color, 2.0, true)

func _toggle_panel() -> void:
	if not is_instance_valid(_panel):
		return
	_panel.visible = not _panel.visible
	_tab_button.set_pressed_no_signal(_panel.visible)
	queue_redraw()

func _on_planet_selected(planet: Node2D) -> void:
	if not is_instance_valid(_panel):
		return
	_active_planet = planet
	_panel.visible = true
	_tab_button.set_pressed_no_signal(true)
	_selected_planet_label.text = "Planet: %s" % planet.name
	_update_selected_count()
	_destination_option.clear()
	_destination_planets.clear()
	_destination_option.disabled = false
	var default_destination := get_destination(planet)
	for destination in _planets:
		if destination != planet:
			_destination_planets.append(destination)
			_destination_option.add_item(destination.name)
	if default_destination != null:
		for index in _destination_option.item_count:
			if _destination_option.get_item_text(index) == default_destination.name:
				_destination_option.select(index)
				break
	queue_redraw()

func _on_destination_selected(index: int) -> void:
	if _active_planet == null or not is_instance_valid(_destination_option):
		return
	if index < 0 or index >= _destination_option.item_count or index >= _destination_planets.size():
		return
	_routes[_active_planet] = _destination_planets[index]
	queue_redraw()

func _on_worker_count_changed(planet: Node2D, _count: int) -> void:
	if _count_labels.has(planet):
		var count_label: Label = _count_labels[planet]
		count_label.text = _count_text(planet)
	if planet == _active_planet:
		_update_selected_count()

func _update_selected_count() -> void:
	if _active_planet == null or not is_instance_valid(_selected_count_label):
		return
	_selected_count_label.text = "Einheiten: %d" % int(_active_planet.get("worker_count"))

func _count_text(planet: Node2D) -> String:
	return "%s: %d" % [planet.name, int(planet.get("worker_count"))]

func get_destination(source: Node2D) -> Node2D:
	var selected = _routes.get(source)
	if selected != null and is_instance_valid(selected):
		return selected as Node2D
	var neighbors := get_neighbors(source)
	return neighbors[0] if not neighbors.is_empty() else null

func get_neighbors(planet: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var slot: int = int(planet.get_meta("layout_slot", -1))
	if slot < 0:
		return result
	var columns: int = int(get_parent().columns)
	var row: int = floori(float(slot) / float(columns))
	var column: int = slot % columns
	for other in _planets:
		if other == planet:
			continue
		var other_slot: int = int(other.get_meta("layout_slot", -1))
		if other_slot < 0:
			continue
		var other_row: int = floori(float(other_slot) / float(columns))
		var other_column: int = other_slot % columns
		if absi(row - other_row) + absi(column - other_column) == 1:
			result.append(other)
	return result
