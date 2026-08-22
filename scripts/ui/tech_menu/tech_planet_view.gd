class_name TechPlanetView
extends RefCounted

## Manages known planet intel view and planet-specific technology research (e.g. Survey, Extraction).

var _theme_config: UIThemeConfig
var _ship_manager: ShipManager

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig) -> void:
	_ship_manager = ship_manager
	_theme_config = theme_config

func build_planets_section(
	container: VBoxContainer,
	state: Node,
	on_refresh_callback: Callable
) -> void:
	if container == null or _ship_manager == null or state == null:
		return

	var planets: Array[Planet] = _ship_manager.get_planets()
	var catalog: TechnologyCatalog = _ship_manager.get_technology_catalog()
	var known: Array[StringName] = state.known_planets_of(GameState.FACTION_PLAYER)
	var planet_technologies: Array[TechnologyDefinition] = catalog.for_category(TechnologyDefinition.CATEGORY_PLANET)

	container.add_child(UIBaseUtils.make_label("BEKANNTE PLANETEN (%d)" % known.size(), _theme_config.heading_text_color, _theme_config.section_font_size))
	var shown: int = 0
	for planet in planets:
		if planet == null or not known.has(planet.planet_id):
			continue
		shown += 1
		var planet_name: String = UIBaseUtils.planet_display_name(planet)
		var faction_id: StringName = state.faction_of(planet.planet_id)
		var own_planet: bool = faction_id == GameState.FACTION_PLAYER
		var faction_str: String = UIBaseUtils.faction_display_name(faction_id)

		container.add_child(UIBaseUtils.make_label("%s  ·  %s" % [planet_name, faction_str], _theme_config.accent_text_color, _theme_config.body_font_size))
		var upgrades: Array[StringName] = state.get_planet_upgrades(planet.planet_id)
		container.add_child(UIBaseUtils.make_label("Ausbauten: %d" % upgrades.size(), _theme_config.muted_text_color, _theme_config.small_font_size))

		var scan_info: Dictionary = state.scan_info_for(GameState.FACTION_PLAYER, planet.planet_id)
		var intel_resource: StringName = state.resource_of(planet.planet_id) if own_planet else scan_info.get("resource_id", &"") as StringName
		var intel_size: String = String(planet.get_size_profile().id).to_upper() if own_planet else String(scan_info.get("size_id", "")).to_upper()
		var intel_slots: int = planet.get_build_slot_count() if own_planet else int(scan_info.get("build_slots", 0))

		if String(intel_resource).is_empty():
			container.add_child(UIBaseUtils.make_label("Scan erforderlich: Ressourcen-Signatur unbekannt.", _theme_config.secondary_text_color, _theme_config.small_font_size))
		else:
			container.add_child(UIBaseUtils.make_label("Signatur: %s  ·  Größe: %s  ·  Bauplätze: %d" % [UIBaseUtils.resource_display_name(intel_resource), intel_size, intel_slots], _theme_config.secondary_text_color, _theme_config.small_font_size))

		if planet_technologies.is_empty():
			container.add_child(UIBaseUtils.make_label("Keine planetaren Technologien definiert.", _theme_config.muted_text_color, _theme_config.small_font_size))
		else:
			for technology in planet_technologies:
				container.add_child(_planet_research_row(technology, state, planet.planet_id, own_planet, on_refresh_callback))

	if shown == 0:
		container.add_child(UIBaseUtils.make_label("Noch keine bekannten Planeten.", _theme_config.muted_text_color, _theme_config.body_font_size))

func _planet_research_row(
	technology: TechnologyDefinition,
	state: Node,
	planet_id: StringName,
	own_planet: bool,
	on_refresh_callback: Callable
) -> Control:
	var researched: bool = state.has_planet_technology(planet_id, technology.id)
	var can_research: bool = own_planet and state.can_research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology.id, _ship_manager.get_technology_catalog())
	var status_text: String
	if researched:
		status_text = "FÜR DIESEN PLANETEN AKTIV"
	elif not own_planet:
		status_text = "Gesperrt (nur eigene bekannte Planeten)"
	elif can_research:
		status_text = "BEREIT · %s" % UIBaseUtils.technology_cost_text(technology, state)
	else:
		status_text = "GESPERRT · %s" % UIBaseUtils.technology_cost_text(technology, state)
	return _planet_technology_card(
		technology,
		status_text,
		researched or not can_research,
		func():
			if state != null and _ship_manager != null:
				state.research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology.id, _ship_manager.get_technology_catalog())
			if on_refresh_callback.is_valid():
				on_refresh_callback.call()
	)

func _planet_technology_card(technology: TechnologyDefinition, status_text: String, disabled: bool, pressed: Callable) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.card_background, Color.TRANSPARENT, _theme_config.panel_border_width, _theme_config.panel_corner_radius)
	)
	row.tooltip_text = technology.description
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _theme_config.card_padding)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(_theme_config.technology_icon_size, _theme_config.technology_icon_size)
	icon.texture = technology.visual_asset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIBaseUtils.make_label(technology.display_name, _theme_config.heading_text_color, _theme_config.body_font_size))
	box.add_child(UIBaseUtils.make_label(UIBaseUtils.research_role(technology), _theme_config.accent_text_color, _theme_config.small_font_size))
	box.add_child(UIBaseUtils.make_label(technology.description, _theme_config.muted_text_color, _theme_config.small_font_size))

	var prerequisite_text: String = _technology_prerequisite_text(technology)
	if not prerequisite_text.is_empty():
		box.add_child(UIBaseUtils.make_label(prerequisite_text, _theme_config.secondary_text_color, _theme_config.small_font_size))

	box.add_child(UIBaseUtils.make_label("Freischaltung: " + technology.mechanic_description, _theme_config.accent_text_color, _theme_config.small_font_size))
	var status_label := UIBaseUtils.make_label(status_text, _theme_config.accent_text_color, _theme_config.small_font_size)
	box.add_child(status_label)

	var research_button := Button.new()
	research_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_button.text = "FORSCHEN"
	research_button.disabled = disabled
	if pressed.is_valid():
		research_button.pressed.connect(pressed)
	research_button.tooltip_text = UIBaseUtils.technology_cost_text(technology)
	box.add_child(research_button)

	content.add_child(box)
	row.add_child(content)
	return row

func _technology_prerequisite_text(technology: TechnologyDefinition) -> String:
	if String(technology.prerequisite_tech_id).is_empty():
		return ""
	var prerequisite: TechnologyDefinition = _ship_manager.get_technology_catalog().resolve(technology.prerequisite_tech_id)
	if prerequisite == null:
		return "Voraussetzung: %s" % technology.prerequisite_tech_id
	return "Voraussetzung: %s" % prerequisite.display_name
