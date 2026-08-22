class_name TechnologyMenu
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

signal opened()
signal closed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ship_manager: ShipManager
var _open := false
var _panel_tween: Tween
var _category: StringName = TechnologyDefinition.CATEGORY_SHIPS
var _countdown_accumulator: float = 0.0

var _research_view := TechResearchView.new()
var _research_ship_view := TechResearchShipView.new()
var _ship_builder_view := TechShipBuilderView.new()
var _planet_view := TechPlanetView.new()

@onready var _ui_root: Control = get_node_or_null("TechTabUI")
@onready var _tab_button: Button = get_node_or_null("TechTabUI/TechTab")
@onready var _panel: PanelContainer = get_node_or_null("TechTabUI/TechPanel")
@onready var _title: Label = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechTitle")
@onready var _category_tabs: HBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/CategoryTabs")
@onready var _list: VBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList")

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ship_manager = ship_manager
	_research_view.setup(ship_manager, _theme_config)
	_research_ship_view.setup(ship_manager, _theme_config)
	_ship_builder_view.setup(ship_manager, _theme_config)
	_planet_view.setup(ship_manager, _theme_config)
	_ensure_node_references()
	_apply_theme()
	_build_category_tabs()
	_connect_signals()
	_set_open(false)
	_refresh()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()

func is_open() -> bool:
	return _open

func close() -> void:
	if _open:
		_set_open(false)

func toggle() -> void:
	_set_open(not _open)

func _ensure_node_references() -> void:
	if _ui_root == null:
		_ui_root = get_node_or_null("TechTabUI")
	if _tab_button == null:
		_tab_button = get_node_or_null("TechTabUI/TechTab")
	if _panel == null:
		_panel = get_node_or_null("TechTabUI/TechPanel")
	if _title == null:
		_title = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechTitle")
	if _category_tabs == null:
		_category_tabs = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/CategoryTabs")
	if _list == null:
		_list = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList")

func _connect_signals() -> void:
	if _tab_button != null and not _tab_button.pressed.is_connected(_on_tab_pressed):
		_tab_button.pressed.connect(_on_tab_pressed)
	var state: Node = _game_state()
	if state == null:
		return
	# Single 5-arg handler covers every signal arity in this menu (largest is
	# planet_scanned at 5 args). Trailing slots fall back to default-null.
	for signal_name in [
		"planet_discovered",
		"planet_scanned",
		"technology_researched",
		"planet_technology_researched",
		"planet_upgraded",
		"worker_factory_built",
		"ship_build_started",
		"ship_assembled",
		"ship_disassembled",
		"research_ship_task_completed",
		"research_ship_idle",
		"persistent_ship_changed",
		"worker_transport_phase_changed",
	]:
		if state.has_signal(signal_name) and not state.get(signal_name).is_connected(_on_state_changed):
			state.get(signal_name).connect(_on_state_changed)

func _build_category_tabs() -> void:
	if _category_tabs == null:
		return
	for child in _category_tabs.get_children():
		_category_tabs.remove_child(child)
		child.queue_free()
	for category in [TechnologyDefinition.CATEGORY_SHIPS, TechnologyDefinition.CATEGORY_MECH, TechnologyDefinition.CATEGORY_PLANET]:
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = _category_label(category)
		button.button_pressed = category == _category
		button.pressed.connect(_on_category_pressed.bind(category, button))
		_category_tabs.add_child(button)

func _category_label(category: StringName) -> String:
	if category == TechnologyDefinition.CATEGORY_SHIPS:
		return "SCHIFFE"
	if category == TechnologyDefinition.CATEGORY_MECH:
		return "MECH"
	if category == TechnologyDefinition.CATEGORY_PLANET:
		return "PLANET"
	return String(category).to_upper()

func _on_category_pressed(category: StringName, button: Button) -> void:
	_category = category
	for child in _category_tabs.get_children():
		if child is Button and child != button:
			(child as Button).set_pressed_no_signal(false)
	_refresh()

func _on_tab_pressed() -> void:
	_set_open(not _open)

func _set_open(open_value: bool) -> void:
	_ensure_node_references()
	_open = open_value
	if _panel != null:
		_panel.visible = open_value
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP if open_value else Control.MOUSE_FILTER_IGNORE
		_animate_panel_transition(open_value)
	if _tab_button != null:
		_tab_button.set_pressed_no_signal(open_value)
		_tab_button.text = "‹  SCHLIESSEN" if open_value else "TECHNOLOGIE ›"
	if open_value:
		_refresh()
		opened.emit()
	else:
		closed.emit()

func _animate_panel_transition(open_value: bool) -> void:
	if not is_instance_valid(_panel):
		return
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if open_value:
		_panel.modulate.a = 0.0
		_panel_tween = create_tween()
		_panel_tween.tween_property(_panel, "modulate:a", 1.0, _theme_config.transition_duration)
	else:
		_panel.modulate.a = 1.0

func _refresh() -> void:
	if _list == null or _ship_manager == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_research_view.clear_countdowns()
	_ship_builder_view.clear_state()

	var state := _game_state()
	if state == null:
		return

	if _category == TechnologyDefinition.CATEGORY_SHIPS:
		_research_view.build_research_section(_list, TechnologyDefinition.CATEGORY_SHIPS, state, _refresh)
		var planets: Array[Planet] = _ship_manager.get_planets()
		_research_ship_view.build_research_ship_and_worker_section(_list, state, planets, _refresh)
		_ship_builder_view.build_ship_builder_section(_list, state, planets, _refresh)
	elif _category == TechnologyDefinition.CATEGORY_MECH:
		_research_view.build_research_section(_list, TechnologyDefinition.CATEGORY_MECH, state, _refresh, "MECHS — SPÄTERE PHASE: Diese Forschung bereitet taktische Bodeneinheiten vor; der Mech-Kampf wird mit Layer 3 aktiv.")
	elif _category == TechnologyDefinition.CATEGORY_PLANET:
		_planet_view.build_planets_section(_list, state, _refresh)

## Largest signal bound here is planet_scanned with 5 args, so the variadic
## handler takes 5 trailing default-null slots to cover every smaller signal.
func _on_state_changed(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	if _open:
		_refresh()

func _process(delta: float) -> void:
	if not _open or _category != TechnologyDefinition.CATEGORY_SHIPS:
		return
	_countdown_accumulator += delta
	if _countdown_accumulator >= 0.5:
		_countdown_accumulator = 0.0
		var state := _game_state()
		if state != null:
			_research_view.update_countdowns(state)
			_ship_builder_view.update_countdowns(state, _refresh)

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()

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
	panel_width = maxf(panel_width, _panel.get_combined_minimum_size().x)
	var edge: float = _theme_config.edge_margin
	_tab_button.offset_left = -_theme_config.tab_width - edge
	_tab_button.offset_top = edge + _theme_config.tab_height + _theme_config.panel_gap
	_tab_button.offset_right = -edge
	_tab_button.offset_bottom = edge + 2.0 * _theme_config.tab_height + _theme_config.panel_gap
	_panel.offset_left = -panel_width - edge
	_panel.offset_top = edge + 2.0 * _theme_config.tab_height + 2.0 * _theme_config.panel_gap
	_panel.offset_right = -edge
	_panel.offset_bottom = -edge

func _apply_theme() -> void:
	if _title != null:
		_title.add_theme_font_size_override("font_size", _theme_config.panel_title_font_size)
		_title.add_theme_color_override("font_color", _theme_config.heading_text_color)
	if _panel != null:
		_panel.add_theme_stylebox_override(
			"panel",
			UIBaseUtils.texture_style_box(
				_theme_config,
				_theme_config.tech_menu_background_texture,
				_theme_config.panel_background,
				float(_theme_config.card_padding)
			)
		)
	if _tab_button != null:
		_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)
		_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
		_tab_button.add_theme_stylebox_override(
			"normal",
			UIBaseUtils.style_box(_theme_config, _theme_config.button_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius)
		)
		_tab_button.add_theme_stylebox_override(
			"hover",
			UIBaseUtils.style_box(_theme_config, _theme_config.button_hover_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius)
		)
		_tab_button.add_theme_stylebox_override(
			"pressed",
			UIBaseUtils.style_box(_theme_config, _theme_config.button_hover_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius)
		)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _open:
		_set_open(false)
		get_viewport().set_input_as_handled()

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
