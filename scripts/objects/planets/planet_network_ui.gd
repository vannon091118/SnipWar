class_name PlanetNetworkUI
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_ECONOMY_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal mission_selected(mission_type: StringName)
signal amount_changed(value: float)
signal send_pressed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _panel_open: bool = false
var _panel_tween: Tween
var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _current_selection: Array[Node2D] = [] as Array[Node2D]
var _pending_income: Dictionary = {}
var _income_flush_scheduled: bool = false

@onready var _tab_button: Button = get_node_or_null("PlanetTabUI/PlanetTab")
@onready var _map_focus_overlay: ColorRect = get_node_or_null("PlanetTabUI/MapFocusOverlay")
@onready var _vault_bar: VaultBar = get_node_or_null("PlanetTabUI/VaultBar")
@onready var _panel: PlanetPanel = get_node_or_null("PlanetTabUI/PlanetPanel")

func update_planets(planets: Array[Node2D]) -> void:
	if _panel == null:
		_ensure_node_references()
	if _panel != null:
		_panel.populate_units(planets)

func setup(planets: Array[Node2D], theme_config: UIThemeConfig = null) -> void:
	layer = 50
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ensure_node_references()
	_apply_theme()
	# Explizite Dependency: EconomyManager kommt aus der GameState-Registrierung
	# (Scene-Boundary), nicht aus einem Szenenbaum-Lookup.
	var economy_manager: Node = null
	var state: Node = GameStateAccess.autoload(self)
	if state != null and state.has_method("get_economy_manager"):
		economy_manager = state.get_economy_manager()
	_vault_bar.setup(_theme_config, economy_manager)
	if not _vault_bar.economy_requested.is_connected(_on_economy_requested):
		_vault_bar.economy_requested.connect(_on_economy_requested)
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
	if _map_focus_overlay == null:
		_map_focus_overlay = get_node_or_null("PlanetTabUI/MapFocusOverlay")
	if _vault_bar == null:
		_vault_bar = get_node_or_null("PlanetTabUI/VaultBar")
	if _panel == null:
		_panel = get_node_or_null("PlanetTabUI/PlanetPanel")

func _apply_theme() -> void:
	if _tab_button != null:
		UIBaseUtils.apply_button_theme(_tab_button, _theme_config)

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
	if not _panel.clear_selection_pressed.is_connected(_on_clear_selection_pressed):
		_panel.clear_selection_pressed.connect(_on_clear_selection_pressed)
	if _panel.has_signal("build_requested") and not _panel.build_requested.is_connected(_on_build_requested):
		_panel.build_requested.connect(_on_build_requested)

signal clear_selection_requested()
signal economy_overview_requested()
signal build_requested()

func _connect_game_state_signals() -> void:
	var state: Node = GameStateAccess.autoload(self)
	if state == null:
		return
	if not state.faction_resources_changed.is_connected(_on_faction_resources_changed):
		state.faction_resources_changed.connect(_on_faction_resources_changed)
	if state.has_signal("credits_changed") and not state.credits_changed.is_connected(_on_credits_changed):
		state.credits_changed.connect(_on_credits_changed)
	if state.has_signal("worker_transport_phase_changed") and not state.worker_transport_phase_changed.is_connected(_on_transport_changed):
		state.worker_transport_phase_changed.connect(_on_transport_changed)
	if not state.resource_generated.is_connected(_on_resource_generated):
		state.resource_generated.connect(_on_resource_generated)
	if state.has_signal("resources_collected") and not state.resources_collected.is_connected(_on_resources_collected):
		state.resources_collected.connect(_on_resources_collected)
	if not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)
	if not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)

func _on_faction_resources_changed(faction: StringName, _resource_id: StringName, _new_amount: int) -> void:
	if faction != GameState.FACTION_PLAYER:
		return
	_refresh_vault()

func _on_credits_changed(faction: StringName, _amount: int) -> void:
	if faction == GameState.FACTION_PLAYER:
		_refresh_vault()

func _on_transport_changed(_transport_id: StringName, _phase: StringName) -> void:
	_refresh_vault()

func _on_resource_generated(planet_id: StringName, resource_id: StringName, amount: int) -> void:
	var state: Node = GameStateAccess.autoload(self)
	if state == null or state.faction_of(planet_id) != GameState.FACTION_PLAYER:
		return
	_queue_income(resource_id, amount)

func _on_resources_collected(faction: StringName, _planet_id: StringName, resource_id: StringName, amount: int) -> void:
	if faction == GameState.FACTION_PLAYER:
		_queue_income(resource_id, amount)

func _queue_income(resource_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_pending_income[resource_id] = int(_pending_income.get(resource_id, 0)) + amount
	if not _income_flush_scheduled:
		_income_flush_scheduled = true
		call_deferred("_flush_income")

func _flush_income() -> void:
	_income_flush_scheduled = false
	var pending: Dictionary = _pending_income.duplicate()
	_pending_income.clear()
	if _vault_bar == null:
		return
	for resource_id in pending:
		_vault_bar.record_income(resource_id as StringName, int(pending[resource_id]), DEFAULT_ECONOMY_CONFIG.tick_interval)

func _on_planet_upgraded(_planet_id: StringName, _upgrade_id: StringName) -> void:
	_refresh_vault()

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	_pending_income.clear()
	_income_flush_scheduled = false
	_vault_bar.clear_income_rates()
	_refresh_vault()

func _on_economy_requested() -> void:
	economy_overview_requested.emit()

func _refresh_vault() -> void:
	if _vault_bar == null:
		return
	var state: Node = GameStateAccess.autoload(self)
	_vault_bar.refresh(state)

# --- delegated panel API (kept identical for PlanetNetwork and preflight) ---

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	_set_panel_open(true)
	_panel.show_planet(planet, destinations, default_destination)
	_refresh_selection_aggregated_panel(_current_selection)
	_apply_responsive_layout()

func set_selection_count(count: int) -> void:
	if _panel != null and _panel.has_method("set_selection_count"):
		_panel.set_selection_count(count)
	_refresh_selection_aggregated_panel(_current_selection)

func refresh_selection_overview(selection: Array[Node2D]) -> void:
	_current_selection = selection.duplicate() as Array[Node2D]
	if _panel != null and _panel.has_method("set_selection_overview"):
		_panel.set_selection_overview(selection)
	_refresh_selection_aggregated_panel(_current_selection)

func _refresh_selection_aggregated_panel(selection: Array[Node2D]) -> void:
	if _panel == null:
		return
	if _panel.has_method("set_selection_count"):
		_panel.set_selection_count(selection.size())
	if _panel.has_method("set_selection_overview"):
		_panel.set_selection_overview(selection)
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

func set_mission_type(mission_type: StringName) -> void:
	_panel.set_mission_type(mission_type)

func has_selectable_amount() -> bool:
	return _panel.has_selectable_amount()

func set_preview(text: String) -> void:
	_panel.set_preview(text)

func set_dispatch_preview(preview: Dictionary) -> void:
	if _panel != null and _panel.has_method("set_dispatch_preview"):
		_panel.set_dispatch_preview(preview)

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
	# Pin the resource bar to the top-left corner so it stays visible and
	# is always clickable for the full economy window.
	if _vault_bar != null:
		var vault_width: float = minf(_theme_config.resource_bar_max_width, viewport_size.x * 0.45)
		_vault_bar.visible = true
		_vault_bar.offset_left = edge
		_vault_bar.offset_top = edge
		_vault_bar.offset_right = edge + vault_width
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

func _on_clear_selection_pressed() -> void:
	clear_selection_requested.emit()

func _on_build_requested() -> void:
	build_requested.emit()

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
		_animate_panel_transition(open)
	if _map_focus_overlay != null:
		_map_focus_overlay.visible = open
	if _tab_button != null:
		_tab_button.set_pressed_no_signal(open)
		_tab_button.text = "‹  SCHLIESSEN" if open else "PLANETEN  ›"
	panel_visibility_changed.emit(open)

func _animate_panel_transition(open: bool) -> void:
	if not is_instance_valid(_panel):
		return
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if open:
		_panel.modulate.a = 0.0
		_panel_tween = create_tween()
		_panel_tween.tween_property(_panel, "modulate:a", 1.0, _theme_config.transition_duration)
	else:
		_panel.modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _panel_open:
		_set_panel_open(false)
		get_viewport().set_input_as_handled()

# --- planet hover tooltip ---

func _process(_delta: float) -> void:
	if is_instance_valid(_tooltip_panel) and _tooltip_panel.visible:
		_update_tooltip_position()

func show_planet_tooltip(planet: Node2D) -> void:
	if not is_instance_valid(_tooltip_panel):
		_build_tooltip()
	var text := "???"
	if _is_planet_known(planet):
		var name_text: String = UIBaseUtils.planet_display_name(planet)
		text = "%s · %d" % [name_text, int(planet.get("worker_count"))]
	_tooltip_label.text = text
	_tooltip_panel.visible = true
	_update_tooltip_position()

func hide_planet_tooltip() -> void:
	if is_instance_valid(_tooltip_panel):
		_tooltip_panel.visible = false

func _build_tooltip() -> void:
	var box: StyleBoxFlat = _style_box(Color(0.05, 0.06, 0.09, 0.94), _theme_config.panel_border, 1, _theme_config.panel_corner_radius)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.name = "PlanetTooltip"
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_theme_stylebox_override("panel", box)
	add_child(_tooltip_panel)
	_tooltip_label = Label.new()
	_tooltip_label.name = "PlanetTooltipLabel"
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)

func _is_planet_known(planet: Node2D) -> bool:
	var state: Node = GameStateAccess.autoload(self)
	if state == null:
		return true
	return state.is_known(planet.get("planet_id"), GameState.FACTION_PLAYER)

func _update_tooltip_position() -> void:
	if not is_instance_valid(_tooltip_panel) or not _tooltip_panel.visible:
		return
	var label_min: Vector2 = _tooltip_label.get_combined_minimum_size()
	_tooltip_panel.size = label_min + Vector2(16.0, 8.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = get_viewport().get_mouse_position() + Vector2(14.0, 14.0)
	pos.x = minf(pos.x, viewport_size.x - _tooltip_panel.size.x - 4.0)
	pos.y = minf(pos.y, viewport_size.y - _tooltip_panel.size.y - 4.0)
	_tooltip_panel.position = pos

# --- signal forwards ---

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_mission_selected(mission_type: StringName) -> void:
	mission_selected.emit(mission_type)

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()
