class_name TechnologyMenu
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"

signal opened()
signal closed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ship_manager: ShipManager
var _open := false
var _panel_tween: Tween
var _category: StringName = TechnologyDefinition.CATEGORY_SHIPS
var _scout_source: OptionButton
var _scout_destination: OptionButton
var _worker_source: OptionButton
var _worker_button: Button
var _builder_source: OptionButton
var _builder_hull: OptionButton
var _builder_scanner: OptionButton
var _builder_modules: Array[OptionButton] = []
var _builder_dynamic: VBoxContainer

@onready var _ui_root: Control = get_node_or_null("TechTabUI")
@onready var _tab_button: Button = get_node_or_null("TechTabUI/TechTab")
@onready var _panel: PanelContainer = get_node_or_null("TechTabUI/TechPanel")
@onready var _title: Label = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechTitle")
@onready var _category_tabs: HBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/CategoryTabs")
@onready var _list: VBoxContainer = get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList")

func _ready() -> void:
	add_to_group("technology_menu")

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
	if state.has_signal("planet_scanned") and not state.planet_scanned.is_connected(_on_planet_scanned):
		state.planet_scanned.connect(_on_planet_scanned)
	if state.has_signal("technology_researched") and not state.technology_researched.is_connected(_on_technology_researched):
		state.technology_researched.connect(_on_technology_researched)
	if state.has_signal("planet_technology_researched") and not state.planet_technology_researched.is_connected(_on_planet_technology_researched):
		state.planet_technology_researched.connect(_on_planet_technology_researched)
	if state.has_signal("planet_upgraded") and not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)
	if state.has_signal("worker_factory_built") and not state.worker_factory_built.is_connected(_on_worker_factory_built):
		state.worker_factory_built.connect(_on_worker_factory_built)

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
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_scout_source = null
	_scout_destination = null
	_worker_source = null
	_worker_button = null
	_builder_source = null
	_builder_hull = null
	_builder_scanner = null
	_builder_modules = []
	_builder_dynamic = null
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
		if technology.requires_discovery and not state.has_scanned_planet(GameState.FACTION_PLAYER):
			continue
		_list.add_child(_research_row(technology, state))
	_list.add_child(_make_separator())
	_list.add_child(_make_label("SCOUT BAUEN", _theme_config.heading_text_color, _theme_config.section_font_size))
	_list.add_child(_make_label("Nur unbekannte benachbarte Gebiete können mit dem Scanner angeflogen werden.", _theme_config.muted_text_color, _theme_config.small_font_size))
	var planets := _ship_manager.get_planets()
	var source_row := _make_label("Startplanet (eigene Werft)", _theme_config.secondary_text_color, _theme_config.small_font_size)
	_list.add_child(source_row)
	_scout_source = OptionButton.new()
	_scout_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_sources(_scout_source, planets, state)
	_scout_source.item_selected.connect(_on_scout_source_changed)
	_list.add_child(_scout_source)
	var destination_row := _make_label("Zielplanet (unbekannter Nachbar)", _theme_config.secondary_text_color, _theme_config.small_font_size)
	_list.add_child(destination_row)
	_scout_destination = OptionButton.new()
	_scout_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_source: Planet = _selected_option_planet(_scout_source)
	_populate_scout_destinations(_scout_destination, selected_source, state)
	_list.add_child(_scout_destination)
	var start_button := Button.new()
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.text = "SCOUT STARTEN"
	var start_source: Planet = _selected_option_planet(_scout_source)
	var can_start: bool = start_source != null and _scout_destination.item_count > 0 and _ship_manager.can_build_scout(start_source)
	start_button.disabled = not can_start
	if not can_start:
		start_button.tooltip_text = "Werft, Scout-Rumpf, Scanner-Drohne, Material und ein freier Bauplatz sind erforderlich."
	start_button.pressed.connect(_on_start_scout)
	_list.add_child(start_button)

	_list.add_child(_make_separator())
	_list.add_child(_make_label("WORKER-FERTIGER", _theme_config.heading_text_color, _theme_config.section_font_size))
	_list.add_child(_make_label("Nach dem ersten Scan und der Forschung wird hier die langsame Worker-Automatik aktiviert.", _theme_config.muted_text_color, _theme_config.small_font_size))
	_worker_source = OptionButton.new()
	_worker_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_sources(_worker_source, planets, state)
	_list.add_child(_worker_source)
	_worker_button = Button.new()
	_worker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worker_button.text = "WORKER-FERTIGER BAUEN"
	_worker_button.pressed.connect(_on_build_workers)
	_list.add_child(_worker_button)
	_refresh_worker_button()
	_refresh_ship_builder(state, planets)

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
		var planet_name: String = planet.display_name if not planet.display_name.is_empty() else String(planet.name)
		var faction_id: StringName = state.faction_of(planet.planet_id)
		var own_planet: bool = faction_id == GameState.FACTION_PLAYER
		var faction_str: String = "EIGEN [A]" if own_planet else ("CPU [B]" if faction_id == GameState.FACTION_CPU else "NEUTRAL")
		_list.add_child(_make_label("%s  ·  %s" % [planet_name, faction_str], _theme_config.accent_text_color, _theme_config.body_font_size))
		var upgrades: Array[StringName] = state.get_planet_upgrades(planet.planet_id)
		_list.add_child(_make_label("Ausbauten: %d" % upgrades.size(), _theme_config.muted_text_color, _theme_config.small_font_size))
		var scan_info: Dictionary = state.scan_info_for(GameState.FACTION_PLAYER, planet.planet_id)
		var intel_resource: StringName = state.resource_of(planet.planet_id) if own_planet else scan_info.get("resource_id", &"") as StringName
		var intel_size: String = String(planet.get_size_profile().id).to_upper() if own_planet else String(scan_info.get("size_id", "")).to_upper()
		var intel_slots: int = planet.get_build_slot_count() if own_planet else int(scan_info.get("build_slots", 0))
		if String(intel_resource).is_empty():
			_list.add_child(_make_label("Scan erforderlich: Ressourcen-Signatur unbekannt.", _theme_config.secondary_text_color, _theme_config.small_font_size))
		else:
			_list.add_child(_make_label("Signatur: %s  ·  Größe: %s  ·  Bauplätze: %d" % [String(intel_resource).capitalize(), intel_size, intel_slots], _theme_config.secondary_text_color, _theme_config.small_font_size))
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

func _on_planet_scanned(_faction: StringName, _planet_id: StringName, _resource_id: StringName, _size_id: StringName, _build_slots: int) -> void:
	_refresh_after_state_change()

func _on_technology_researched(_faction: StringName, _technology_id: StringName) -> void:
	_refresh_after_state_change()

func _on_planet_technology_researched(_planet_id: StringName, _technology_id: StringName) -> void:
	_refresh_after_state_change()

func _on_planet_upgraded(_planet_id: StringName, _upgrade_id: StringName) -> void:
	_refresh_after_state_change()

func _on_worker_factory_built(_planet_id: StringName) -> void:
	_refresh_after_state_change()

func _populate_scout_sources(option: OptionButton, planets: Array[Planet], state: Node) -> void:
	option.clear()
	for planet in planets:
		if state.faction_of(planet.planet_id) == GameState.FACTION_PLAYER and state.has_planet_upgrade(planet.planet_id, SHIPYARD_UPGRADE_ID):
			option.add_item(planet.name)
			option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func _populate_scout_destinations(option: OptionButton, source: Planet, state: Node) -> void:
	option.clear()
	if source != null:
		for planet in _ship_manager.get_scan_destinations(source):
			if not state.is_known(planet.planet_id, GameState.FACTION_PLAYER):
				option.add_item(planet.name)
				option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func _selected_option_planet(option: OptionButton) -> Planet:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return null
	return option.get_item_metadata(option.selected) as Planet

func _on_scout_source_changed(_index: int) -> void:
	if _scout_destination == null:
		return
	var state: Node = _game_state()
	if state != null:
		_populate_scout_destinations(_scout_destination, _selected_option_planet(_scout_source), state)

func _refresh_worker_button() -> void:
	if _worker_button == null:
		return
	var source: Planet = _selected_option_planet(_worker_source)
	_worker_button.disabled = source == null or not _ship_manager.can_build_workers(source)
	if source == null:
		_worker_button.tooltip_text = "Eigene Werft und Worker-Automatik nach einem Scan erforderlich."
	else:
		_worker_button.tooltip_text = "Bauplätze: %d" % source.get_build_slot_count()

func _on_build_workers() -> void:
	var source: Planet = _selected_option_planet(_worker_source)
	if source != null and _ship_manager.build_workers(source):
		_refresh()

func _refresh_ship_builder(state: Node, planets: Array[Planet]) -> void:
	if _ship_manager == null:
		return
	_list.add_child(_make_separator())
	_list.add_child(_make_label("SCHIFFSWERFT — SHOP", _theme_config.heading_text_color, _theme_config.section_font_size))
	_list.add_child(_make_label("Teile kaufen, im Hangar montieren und bei Bedarf wieder zerlegen.", _theme_config.muted_text_color, _theme_config.small_font_size))
	_list.add_child(_make_label("Startplanet (eigene Werft)", _theme_config.secondary_text_color, _theme_config.small_font_size))
	_builder_source = OptionButton.new()
	_builder_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_sources(_builder_source, planets, state)
	_builder_source.item_selected.connect(_on_builder_source_changed)
	_list.add_child(_builder_source)
	_builder_dynamic = VBoxContainer.new()
	_builder_dynamic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_builder_dynamic.add_theme_constant_override("separation", _theme_config.list_separation)
	_list.add_child(_builder_dynamic)
	_populate_builder_dynamic(state)

func _populate_builder_dynamic(state: Node) -> void:
	if _builder_dynamic == null:
		return
	for child in _builder_dynamic.get_children():
		_builder_dynamic.remove_child(child)
		child.queue_free()
	_builder_hull = null
	_builder_scanner = null
	_builder_modules = []
	var source: Planet = _selected_option_planet(_builder_source)
	if source == null:
		_builder_dynamic.add_child(_make_label("Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen.", _theme_config.muted_text_color, _theme_config.small_font_size))
		return
	var catalog: ShipPartCatalog = _ship_manager.get_part_catalog()
	var inventory: Dictionary = state.get_ship_part_inventory(source.planet_id)
	_builder_dynamic.add_child(_make_label("TEILE KAUFEN", _theme_config.heading_text_color, _theme_config.section_font_size))
	for part in catalog.parts:
		if part == null:
			continue
		var owned: int = int(inventory.get(part.id, 0))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", _theme_config.card_padding)
		var label := _make_label("%s — %d %s  (Besitz: %d)" % [part.display_name, part.cost_amount, String(part.cost_resource), owned], _theme_config.secondary_text_color, _theme_config.small_font_size)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy := Button.new()
		buy.text = "KAUFEN"
		buy.disabled = not _ship_manager.can_buy_part(source, part.id)
		if buy.disabled:
			buy.tooltip_text = "Kosten: %d %s" % [part.cost_amount, String(part.cost_resource)]
		buy.pressed.connect(_on_buy_part.bind(part.id))
		row.add_child(buy)
		_builder_dynamic.add_child(row)
	_builder_dynamic.add_child(_make_separator())
	_builder_dynamic.add_child(_make_label("MONTAGE", _theme_config.heading_text_color, _theme_config.section_font_size))
	_builder_dynamic.add_child(_make_label("Hülle", _theme_config.secondary_text_color, _theme_config.small_font_size))
	_builder_hull = _builder_slot_option(inventory, ShipPartDefinition.SLOT_HULL)
	_builder_dynamic.add_child(_builder_hull)
	_builder_dynamic.add_child(_make_label("Scanner", _theme_config.secondary_text_color, _theme_config.small_font_size))
	_builder_scanner = _builder_slot_option(inventory, ShipPartDefinition.SLOT_SCANNER)
	_builder_dynamic.add_child(_builder_scanner)
	for index in catalog.max_module_slots:
		_builder_dynamic.add_child(_make_label("Modul %d" % (index + 1), _theme_config.secondary_text_color, _theme_config.small_font_size))
		var module_option: OptionButton = _builder_slot_option(inventory, ShipPartDefinition.SLOT_MODULE, true)
		_builder_modules.append(module_option)
		_builder_dynamic.add_child(module_option)
	var assemble := Button.new()
	assemble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assemble.text = "KOMBINIEREN"
	assemble.disabled = not _builder_can_assemble()
	assemble.pressed.connect(_on_assemble_ship)
	_builder_dynamic.add_child(assemble)
	_builder_dynamic.add_child(_make_separator())
	_builder_dynamic.add_child(_make_label("GEBAUTE SCHIFFE", _theme_config.heading_text_color, _theme_config.section_font_size))
	var assemblies: Dictionary = state.get_ship_assemblies(source.planet_id)
	if assemblies.is_empty():
		_builder_dynamic.add_child(_make_label("Noch keine Schiffe montiert.", _theme_config.muted_text_color, _theme_config.small_font_size))
	else:
		for ship_value in assemblies:
			var ship_id: StringName = ship_value as StringName
			var ship_row := HBoxContainer.new()
			ship_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ship_row.add_theme_constant_override("separation", _theme_config.card_padding)
			var ship_label := _make_label(_assembly_description(catalog, assemblies[ship_id]), _theme_config.secondary_text_color, _theme_config.small_font_size)
			ship_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ship_row.add_child(ship_label)
			var disassemble := Button.new()
			disassemble.text = "ZERLEGEN"
			disassemble.pressed.connect(_on_disassemble_ship.bind(ship_id))
			ship_row.add_child(disassemble)
			_builder_dynamic.add_child(ship_row)

func _builder_slot_option(inventory: Dictionary, slot_type: StringName, allow_none: bool = false) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var catalog: ShipPartCatalog = _ship_manager.get_part_catalog()
	if allow_none:
		option.add_item("— (kein Modul)")
		option.set_item_metadata(0, &"")
	for part in catalog.for_slot(slot_type):
		if int(inventory.get(part.id, 0)) > 0:
			option.add_item(part.display_name)
			option.set_item_metadata(option.item_count - 1, part.id)
	option.disabled = option.item_count == 0
	return option

func _builder_selected_part(option: OptionButton) -> StringName:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return &""
	var meta: Variant = option.get_item_metadata(option.selected)
	return meta as StringName if meta != null else &""

func _builder_can_assemble() -> bool:
	var source: Planet = _selected_option_planet(_builder_source)
	if source == null or _builder_hull == null or _builder_scanner == null:
		return false
	var hull_id := _builder_selected_part(_builder_hull)
	var scanner_id := _builder_selected_part(_builder_scanner)
	if String(hull_id).is_empty() or String(scanner_id).is_empty():
		return false
	var module_ids: Array = []
	for option in _builder_modules:
		var module_id := _builder_selected_part(option)
		if not String(module_id).is_empty():
			module_ids.append(module_id)
	return _ship_manager.can_assemble_ship(source, hull_id, scanner_id, module_ids)

func _assembly_description(catalog: ShipPartCatalog, assembly: Dictionary) -> String:
	var hull := catalog.resolve(assembly.get("hull", &"") as StringName)
	var scanner := catalog.resolve(assembly.get("scanner", &"") as StringName)
	var hull_name: String = hull.display_name if hull != null else String(assembly.get("hull", ""))
	var scanner_name: String = scanner.display_name if scanner != null else String(assembly.get("scanner", ""))
	var module_names: Array[String] = []
	for module_value in assembly.get("modules", []):
		var module := catalog.resolve(module_value as StringName)
		module_names.append(module.display_name if module != null else String(module_value))
	var text := "%s + %s" % [hull_name, scanner_name]
	if not module_names.is_empty():
		text += " + " + ", ".join(module_names)
	return text

func _on_builder_source_changed(_index: int) -> void:
	_populate_builder_dynamic(_game_state())

func _on_buy_part(part_id: StringName) -> void:
	var source: Planet = _selected_option_planet(_builder_source)
	if source != null and _ship_manager.buy_part(source, part_id):
		_populate_builder_dynamic(_game_state())

func _on_assemble_ship() -> void:
	var source: Planet = _selected_option_planet(_builder_source)
	if source == null or _builder_hull == null or _builder_scanner == null:
		return
	var hull_id := _builder_selected_part(_builder_hull)
	var scanner_id := _builder_selected_part(_builder_scanner)
	var module_ids: Array = []
	for option in _builder_modules:
		var module_id := _builder_selected_part(option)
		if not String(module_id).is_empty():
			module_ids.append(module_id)
	_ship_manager.assemble_ship(source, hull_id, scanner_id, module_ids)
	_populate_builder_dynamic(_game_state())

func _on_disassemble_ship(ship_id: StringName) -> void:
	var source: Planet = _selected_option_planet(_builder_source)
	if source != null:
		_ship_manager.disassemble_ship(source, ship_id)
	_populate_builder_dynamic(_game_state())

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
