class_name TechnologyMenu
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"

signal opened()
signal closed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ship_manager: ShipManager
var _open := false
var _category: StringName = TechnologyDefinition.CATEGORY_SHIPS
var _scout_source: OptionButton
var _scout_destination: OptionButton

@onready var _ui_root: Control = get_node_or_null("TechTabUI")
@onready var _tab_button: Button = get_node_or_null("TechTabUI/TechTab")
@onready var _panel: PanelContainer = get_node_or_null("TechTabUI/TechPanel")
@onready var _title: Label = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechTitle")
@onready var _category_tabs: HBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/CategoryTabs")
@onready var _list: VBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList")

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ship_manager = ship_manager
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
	if state.has_signal("planet_discovered") and not state.planet_discovered.is_connected(_on_planet_discovered):
		state.planet_discovered.connect(_on_planet_discovered)
	if state.has_signal("technology_researched") and not state.technology_researched.is_connected(_on_technology_researched):
		state.technology_researched.connect(_on_technology_researched)
	if state.has_signal("planet_technology_researched") and not state.planet_technology_researched.is_connected(_on_planet_technology_researched):
		state.planet_technology_researched.connect(_on_planet_technology_researched)
	if state.has_signal("planet_upgraded") and not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)

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
	if _tab_button != null:
		_tab_button.set_pressed_no_signal(open_value)
		_tab_button.text = "‹  SCHLIESSEN" if open_value else "TECHNOLOGIE ›"
	if open_value:
		_refresh()
		opened.emit()
	else:
		closed.emit()

func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_scout_source = null
	_scout_destination = null
	if _ship_manager == null:
		return
	if _category == TechnologyDefinition.CATEGORY_SHIPS:
		_refresh_ships()
	elif _category == TechnologyDefinition.CATEGORY_MECH:
		_refresh_research(TechnologyDefinition.CATEGORY_MECH, "Layer-3-Mechs werden sichtbar geführt, aber erst mit Layer 3 aktiv.")
	elif _category == TechnologyDefinition.CATEGORY_PLANET:
		_refresh_planets()

func _refresh_ships() -> void:
	var state := _game_state()
	if state == null:
		return
	var catalog: TechnologyCatalog = _ship_manager.get_technology_catalog()
	for technology in catalog.for_category(TechnologyDefinition.CATEGORY_SHIPS):
		_list.add_child(_research_row(technology, state))
	_list.add_child(_make_separator())
	_list.add_child(_make_label("SCOUT BAUEN", _theme_config.heading_text_color, _theme_config.section_font_size))
	_list.add_child(_make_label("Voraussetzung: Orbitale Werft auf dem Startplaneten, Rumpf + Scanner-Drohne erforscht.", _theme_config.muted_text_color, _theme_config.small_font_size))
	var planets := _ship_manager.get_planets()
	var source_row := _make_label("Startplanet (eigene Werft)", _theme_config.secondary_text_color, _theme_config.small_font_size)
	_list.add_child(source_row)
	_scout_source = OptionButton.new()
	_scout_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_sources(_scout_source, planets, state)
	_list.add_child(_scout_source)
	var destination_row := _make_label("Zielplanet (unbekannt)", _theme_config.secondary_text_color, _theme_config.small_font_size)
	_list.add_child(destination_row)
	_scout_destination = OptionButton.new()
	_scout_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_destinations(_scout_destination, planets, state)
	_list.add_child(_scout_destination)
	var start_button := Button.new()
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.text = "SCOUT STARTEN"
	start_button.disabled = _scout_source.item_count == 0 or _scout_destination.item_count == 0
	start_button.pressed.connect(_on_start_scout)
	_list.add_child(start_button)

func _refresh_research(category: StringName, note: String) -> void:
	var state := _game_state()
	if state == null:
		return
	var catalog: TechnologyCatalog = _ship_manager.get_technology_catalog()
	var entries := catalog.for_category(category)
	if entries.is_empty():
		_list.add_child(_make_label("Keine Technologien verfügbar.", _theme_config.muted_text_color, _theme_config.body_font_size))
		return
	_list.add_child(_make_label(note, _theme_config.muted_text_color, _theme_config.small_font_size))
	for technology in entries:
		_list.add_child(_research_row(technology, state))

func _refresh_planets() -> void:
	var state: Node = _game_state()
	if state == null:
		return
	var planets: Array[Planet] = _ship_manager.get_planets()
	var catalog: TechnologyCatalog = _ship_manager.get_technology_catalog()
	var known: Array[StringName] = state.known_planets_of(GameState.FACTION_PLAYER)
	var planet_technologies: Array[TechnologyDefinition] = catalog.for_category(TechnologyDefinition.CATEGORY_PLANET)
	_list.add_child(_make_label("BEKANNTE PLANETEN (%d)" % known.size(), _theme_config.heading_text_color, _theme_config.section_font_size))
	var shown: int = 0
	for planet in planets:
		if not known.has(planet.planet_id):
			continue
		shown += 1
		var planet_name: String = planet.display_name if not planet.display_name.is_empty() else planet.name
		var faction_id: StringName = state.faction_of(planet.planet_id)
		var own_planet: bool = faction_id == GameState.FACTION_PLAYER
		var faction_str: String = "EIGEN [A]" if own_planet else ("CPU [B]" if faction_id == GameState.FACTION_CPU else "NEUTRAL")
		_list.add_child(_make_label("%s  ·  %s" % [planet_name, faction_str], _theme_config.accent_text_color, _theme_config.body_font_size))
		var upgrades: Array[StringName] = state.get_planet_upgrades(planet.planet_id)
		_list.add_child(_make_label("Ausbauten: %d" % upgrades.size(), _theme_config.muted_text_color, _theme_config.small_font_size))
		if planet_technologies.is_empty():
			_list.add_child(_make_label("Keine planetaren Technologien definiert.", _theme_config.muted_text_color, _theme_config.small_font_size))
		else:
			for technology in planet_technologies:
				_list.add_child(_planet_research_row(technology, state, planet.planet_id, own_planet))
	if shown == 0:
		_list.add_child(_make_label("Noch keine bekannten Planeten.", _theme_config.muted_text_color, _theme_config.body_font_size))

func _research_row(technology: TechnologyDefinition, state: Node) -> Control:
	var researched: bool = state.has_technology(GameState.FACTION_PLAYER, technology.id)
	var can_research: bool = state.can_research_technology(GameState.FACTION_PLAYER, technology.id, _ship_manager.get_technology_catalog())
	var status_text: String
	if researched:
		status_text = "FREIGESCHALTET"
	elif can_research:
		status_text = "Kosten: %d %s" % [technology.cost_amount, String(technology.cost_resource)]
	else:
		status_text = "Gesperrt (Kosten/Voraussetzung fehlt)"
	return _technology_card(technology, status_text, researched or not can_research, _on_research.bind(technology.id))

func _planet_research_row(technology: TechnologyDefinition, state: Node, planet_id: StringName, own_planet: bool) -> Control:
	var researched: bool = state.has_planet_technology(planet_id, technology.id)
	var can_research: bool = own_planet and state.can_research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology.id, _ship_manager.get_technology_catalog())
	var status_text: String
	if researched:
		status_text = "FÜR DIESEN PLANETEN AKTIV"
	elif not own_planet:
		status_text = "Gesperrt (nur eigene bekannte Planeten)"
	elif can_research:
		status_text = "Kosten: %d %s" % [technology.cost_amount, String(technology.cost_resource)]
	else:
		status_text = "Gesperrt (Kosten/Voraussetzung fehlt)"
	return _technology_card(technology, status_text, researched or not can_research, _on_planet_research.bind(planet_id, technology.id))

func _technology_card(technology: TechnologyDefinition, status_text: String, disabled: bool, pressed: Callable) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _style_box(_theme_config.card_background, Color.TRANSPARENT, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
	row.tooltip_text = technology.description
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _theme_config.card_padding)
	content.add_child(_technology_icon(technology))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_make_label(technology.display_name, _theme_config.heading_text_color, _theme_config.body_font_size))
	box.add_child(_make_label(technology.description, _theme_config.muted_text_color, _theme_config.small_font_size))
	var prerequisite_text: String = _technology_prerequisite_text(technology)
	if not prerequisite_text.is_empty():
		box.add_child(_make_label(prerequisite_text, _theme_config.secondary_text_color, _theme_config.small_font_size))
	box.add_child(_make_label(technology.mechanic_description, _theme_config.accent_text_color, _theme_config.small_font_size))
	box.add_child(_make_label(status_text, _theme_config.accent_text_color, _theme_config.small_font_size))
	var research_button := Button.new()
	research_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_button.text = "FORSCHEN"
	research_button.disabled = disabled
	if pressed.is_valid():
		research_button.pressed.connect(pressed)
	box.add_child(research_button)
	content.add_child(box)
	row.add_child(content)
	return row

func _technology_icon(technology: TechnologyDefinition) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(_theme_config.technology_icon_size, _theme_config.technology_icon_size)
	icon.texture = technology.visual_asset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _technology_prerequisite_text(technology: TechnologyDefinition) -> String:
	if String(technology.prerequisite_tech_id).is_empty():
		return ""
	var prerequisite: TechnologyDefinition = _ship_manager.get_technology_catalog().resolve(technology.prerequisite_tech_id)
	if prerequisite == null:
		return "Voraussetzung: %s" % technology.prerequisite_tech_id
	return "Voraussetzung: %s" % prerequisite.display_name

func _on_research(technology_id: StringName) -> void:
	var state: Node = _game_state()
	if state != null and _ship_manager != null:
		state.research_technology(GameState.FACTION_PLAYER, technology_id, _ship_manager.get_technology_catalog())
	_refresh()

func _on_planet_research(planet_id: StringName, technology_id: StringName) -> void:
	var state: Node = _game_state()
	if state != null and _ship_manager != null:
		state.research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology_id, _ship_manager.get_technology_catalog())
	_refresh()

func _refresh_after_state_change() -> void:
	if _open:
		_refresh()

func _on_planet_discovered(_faction: StringName, _planet_id: StringName) -> void:
	_refresh_after_state_change()

func _on_technology_researched(_faction: StringName, _technology_id: StringName) -> void:
	_refresh_after_state_change()

func _on_planet_technology_researched(_planet_id: StringName, _technology_id: StringName) -> void:
	_refresh_after_state_change()

func _on_planet_upgraded(_planet_id: StringName, _upgrade_id: StringName) -> void:
	_refresh_after_state_change()

func _populate_scout_sources(option: OptionButton, planets: Array[Planet], state: Node) -> void:
	option.clear()
	for planet in planets:
		if state.faction_of(planet.planet_id) == GameState.FACTION_PLAYER and state.has_planet_upgrade(planet.planet_id, SHIPYARD_UPGRADE_ID):
			option.add_item(planet.name)
			option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func _populate_scout_destinations(option: OptionButton, planets: Array[Planet], state: Node) -> void:
	option.clear()
	for planet in planets:
		if not state.is_known(planet.planet_id, GameState.FACTION_PLAYER):
			option.add_item(planet.name)
			option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func _on_start_scout() -> void:
	if _ship_manager == null or _scout_source == null or _scout_destination == null:
		return
	if _scout_source.item_count == 0 or _scout_destination.item_count == 0:
		return
	var source: Planet = _scout_source.get_item_metadata(_scout_source.selected) as Planet
	var destination: Planet = _scout_destination.get_item_metadata(_scout_destination.selected) as Planet
	if source != null and destination != null:
		_ship_manager.build_scout(source, destination)
	_refresh()

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
		_panel.add_theme_stylebox_override("panel", _style_box(_theme_config.panel_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
	if _tab_button != null:
		_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)
		_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
		_tab_button.add_theme_stylebox_override("normal", _style_box(_theme_config.button_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
		_tab_button.add_theme_stylebox_override("hover", _style_box(_theme_config.button_hover_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
		_tab_button.add_theme_stylebox_override("pressed", _style_box(_theme_config.button_hover_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))

func _style_box(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	return _theme_config.make_style_box(background, border, border_width, radius)

func _make_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return separator

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _open:
		_set_open(false)
		get_viewport().set_input_as_handled()

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
