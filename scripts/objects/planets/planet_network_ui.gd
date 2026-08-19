class_name PlanetNetworkUI
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal mission_selected(mission_type: StringName)
signal amount_changed(value: float)
signal send_pressed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _panel_open: bool = false

@onready var _tab_button: Button = get_node_or_null("PlanetTabUI/PlanetTab")
@onready var _vault_bar: VaultBar = get_node_or_null("PlanetTabUI/VaultBar")
@onready var _panel: PlanetPanel = get_node_or_null("PlanetTabUI/PlanetPanel")

func setup(planets: Array[Node2D], theme_config: UIThemeConfig = null) -> void:
	layer = 50
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ensure_node_references()
	_apply_theme()
	_vault_bar.setup(_theme_config)
	_panel.setup(_theme_config)
	_panel.populate_units(planets)
	_connect_tab_signal()
	_connect_panel_signals()
	_connect_game_state_signals()
	_set_panel_open(false)
	_refresh_vault()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()

func _ensure_node_references() -> void:
	if _tab_button == null:
		_tab_button = get_node_or_null("PlanetTabUI/PlanetTab")
	if _vault_bar == null:
		_vault_bar = get_node_or_null("PlanetTabUI/VaultBar")
	if _panel == null:
		_panel = get_node_or_null("PlanetTabUI/PlanetPanel")

func _apply_theme() -> void:
	if _tab_button != null:
		_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
		_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)
		_tab_button.add_theme_stylebox_override("normal", _style_box(_theme_config.button_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
		_tab_button.add_theme_stylebox_override("hover", _style_box(_theme_config.button_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
		_tab_button.add_theme_stylebox_override("pressed", _style_box(_theme_config.button_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))

func _style_box(background: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 0) -> StyleBoxFlat:
	return _theme_config.make_style_box(background, border, border_width, radius)

func _connect_tab_signal() -> void:
	if _tab_button != null and not _tab_button.pressed.is_connected(_toggle_panel):
		_tab_button.pressed.connect(_toggle_panel)

func _connect_panel_signals() -> void:
	if _panel == null:
		return
	if not _panel.destination_selected.is_connected(_on_destination_selected):
		_panel.destination_selected.connect(_on_destination_selected)
	if not _panel.mission_selected.is_connected(_on_mission_selected):
		_panel.mission_selected.connect(_on_mission_selected)
	if not _panel.amount_changed.is_connected(_on_amount_changed):
		_panel.amount_changed.connect(_on_amount_changed)
	if not _panel.send_pressed.is_connected(_on_send_pressed):
		_panel.send_pressed.connect(_on_send_pressed)
	if not _panel.layout_requested.is_connected(_on_panel_layout_requested):
		_panel.layout_requested.connect(_on_panel_layout_requested)

func _connect_game_state_signals() -> void:
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null:
		return
	if not state.faction_resources_changed.is_connected(_on_faction_resources_changed):
		state.faction_resources_changed.connect(_on_faction_resources_changed)
	if not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)
	if not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)

func _on_faction_resources_changed(faction: StringName, _resource_id: StringName, _new_amount: int) -> void:
	if faction != GameState.FACTION_PLAYER:
		return
	_refresh_vault()

func _on_planet_upgraded(_planet_id: StringName, _upgrade_id: StringName) -> void:
	_refresh_vault()

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	_refresh_vault()

func _refresh_vault() -> void:
	if _vault_bar == null:
		return
	var state: Node = get_tree().root.get_node_or_null("GameState")
	_vault_bar.refresh(state)

# --- delegated panel API (kept identical for PlanetNetwork and preflight) ---

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	_set_panel_open(true)
	_panel.show_planet(planet, destinations, default_destination)
	_apply_responsive_layout()

func set_destinations(destinations: Array[Node2D], default_destination: Node2D) -> void:
	_panel.set_destinations(destinations, default_destination)

func update_count(planet: Node2D) -> void:
	_panel.update_count(planet)

func set_selected_count(count: int) -> void:
	_panel.set_selected_count(count)

func set_amount_bounds(bounds: Vector2i) -> void:
	_panel.set_amount_bounds(bounds)

func reset_amount() -> void:
	_panel.reset_amount()

func selected_amount() -> int:
	return _panel.selected_amount()

func selected_mission_type() -> StringName:
	return _panel.selected_mission_type()

func has_selectable_amount() -> bool:
	return _panel.has_selectable_amount()

func set_preview(text: String) -> void:
	_panel.set_preview(text)

func is_panel_visible() -> bool:
	return _panel_open and is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	_toggle_panel()

func close_panel() -> void:
	_set_panel_open(false)

func get_panel() -> PanelContainer:
	return _panel

func index_of_destination(destination_name: String) -> int:
	return _panel.index_of_destination(destination_name)

func get_destination_option() -> OptionButton:
	return _panel.get_destination_option()

func get_amount_slider() -> HSlider:
	return _panel.get_amount_slider()

func get_preview_label() -> Label:
	return _panel.get_preview_label()

func get_send_button() -> Button:
	return _panel.get_send_button()

func get_count_label(planet: Node2D) -> Label:
	return _panel.get_count_label(planet)

# --- responsive layout and panel visibility ---

func _apply_responsive_layout() -> void:
	if not is_instance_valid(_tab_button) or not is_instance_valid(_panel):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var panel_width: float = clampf(
		viewport_size.x * _theme_config.panel_width_ratio,
		_theme_config.panel_min_width,
		_theme_config.panel_max_width
	)
	var minimum_panel_width: float = _panel.get_combined_minimum_size().x
	panel_width = maxf(panel_width, minimum_panel_width)
	var edge: float = _theme_config.edge_margin
	var panel_left: float = viewport_size.x - panel_width - edge

	# Keep the resource HUD centered in the map area instead of underneath the panel.
	if _vault_bar != null:
		var available_vault_width: float = maxf(0.0, panel_left - edge * 2.0)
		var vault_width: float = minf(_theme_config.resource_bar_max_width, available_vault_width)
		_vault_bar.visible = vault_width > 0.0
		if _vault_bar.visible:
			var vault_left: float = maxf(edge, (panel_left - vault_width) * 0.5)
			_vault_bar.offset_left = vault_left
			_vault_bar.offset_top = edge
			_vault_bar.offset_right = vault_left + vault_width
			_vault_bar.offset_bottom = edge + _theme_config.resource_bar_height

	# The tab is a compact handle, not a second full-width title bar.
	_tab_button.offset_left = -_theme_config.tab_width - edge
	_tab_button.offset_top = edge
	_tab_button.offset_right = -edge
	_tab_button.offset_bottom = edge + _theme_config.tab_height
	_panel.offset_left = -panel_width - edge
	_panel.offset_top = edge + _theme_config.tab_height + _theme_config.panel_gap
	_panel.offset_right = -edge
	_panel.offset_bottom = -edge

func _on_panel_layout_requested() -> void:
	call_deferred("_apply_responsive_layout")

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()

func _toggle_panel() -> void:
	_set_panel_open(not _panel_open)

func _set_panel_open(open: bool) -> void:
	_ensure_node_references()
	_panel_open = open
	if _panel != null:
		_panel.visible = open
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if _tab_button != null:
		_tab_button.set_pressed_no_signal(open)
		_tab_button.text = "‹  SCHLIESSEN" if open else "PLANETEN  ›"
	panel_visibility_changed.emit(open)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _panel_open:
		_set_panel_open(false)
		get_viewport().set_input_as_handled()

# --- signal forwards ---

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_mission_selected(mission_type: StringName) -> void:
	mission_selected.emit(mission_type)

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()
