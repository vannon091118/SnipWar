class_name PlanetDossierView
extends Control

## Vollbild-Bau-Hub ([P]): linke Spalte listet alle EIGENEN Planeten mit
## Hangar-Auslastung und laufenden Bauten; die rechte Spalte zeigt den
## gewählten Planeten mit visuellen Bauplatz-Slots, Gebäude-Kacheln
## (Status-Farben inkl. Baufortschritt und Abbruch) sowie planetarer
## Forschung. Ersetzt die frühere reine Dossier-Ansicht und übernimmt die
## Bau-Verwaltung vom rechten PlanetPanel und dem PLANET-Tab des Tech-Menüs.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")

const REFRESH_INTERVAL := 0.5

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _upgrade_catalog: PlanetUpgradeCatalog = DEFAULT_UPGRADE_CATALOG
var _technology_catalog: TechnologyCatalog = DEFAULT_TECHNOLOGY_CATALOG
var _state: Node
var _planet: Planet
var _own_planets: Array[Planet] = []
var _phase := 0.0
var _refresh_accumulator := 0.0
var _signals_bound := false

var _planets_list: VBoxContainer
var _left_info: VBoxContainer
var _slot_content: VBoxContainer
var _build_bars: Array[ProgressBar] = []
var _build_labels: Array[Label] = []
var _build_scroll: ScrollContainer

func setup(theme_config: UIThemeConfig = null, upgrade_catalog: PlanetUpgradeCatalog = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_upgrade_catalog = upgrade_catalog if upgrade_catalog != null else DEFAULT_UPGRADE_CATALOG
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func populate(planet: Planet, state: Node) -> void:
	_state = state
	if planet != null and is_instance_valid(planet):
		_planet = planet
	_collect_own_planets()
	if (_planet == null or not is_instance_valid(_planet)) and not _own_planets.is_empty():
		_planet = _own_planets[0]
	_rebuild_selector()
	_rebuild_all()
	queue_redraw()

## Der Dossier-Host fügt die View erst nach populate() in den Baum ein;
## GameState-Signale werden deshalb verzögert beim Enter gebunden.
func _ready() -> void:
	_bind_state_signals()

func _bind_state_signals() -> void:
	if _signals_bound or _state == null:
		return
	_signals_bound = true
	for signal_name in [
		"planet_upgraded",
		"worker_factory_built",
		"faction_resources_changed",
		"credits_changed",
		"ship_build_started",
		"ship_assembled",
		"ship_disassembled",
		"planet_technology_researched",
		"technology_researched",
	]:
		if _state.has_signal(signal_name) and not _state.get(signal_name).is_connected(_on_state_changed):
			_state.get(signal_name).connect(_on_state_changed)

func _on_state_changed(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	if is_visible_in_tree():
		call_deferred("_rebuild_all")

# ── Aufbau ─────────────────────────────────────────────────────────────

## Kontext-gated Sub-Menü-Navigation: Die Hotkeys feuern NUR, solange dieses
## Dossier offen ist (die View existiert dann ausschließlich im Baum). [1]-[9]
## wählen den n-ten eigenen Planeten, Bild Auf/Ab scrollt die Bau-Slots.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		if event.echo:
			return
		var index: int = int(event.keycode) - int(KEY_1)
		if index < _own_planets.size():
			_select_planet(_own_planets[index])
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_PAGEUP:
		if _build_scroll != null:
			_build_scroll.scroll_vertical = maxi(_build_scroll.scroll_vertical - int(_build_scroll.size.y * 0.8), 0)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_PAGEDOWN:
		if _build_scroll != null:				_build_scroll.scroll_vertical = mini(_build_scroll.scroll_vertical + int(_build_scroll.size.y * 0.8), int(_build_scroll.get_v_scroll_bar().max_value))
		get_viewport().set_input_as_handled()
func _build_ui() -> void:
	# Linke Spalte: Planeten-Auswahl (Mitte) + Info (unten), oben bleibt die
	# gezeichnete Planetenscheibe.
	_planets_list = VBoxContainer.new()
	_planets_list.name = "PlanetsList"
	_planets_list.anchor_left = 0.0
	_planets_list.anchor_top = 0.50
	_planets_list.anchor_right = 0.44
	_planets_list.anchor_bottom = 0.72
	_planets_list.offset_left = 16.0
	_planets_list.offset_top = 4.0
	_planets_list.offset_right = -16.0
	_planets_list.offset_bottom = -4.0
	_planets_list.add_theme_constant_override("separation", _theme_config.list_separation)
	add_child(_planets_list)

	_left_info = VBoxContainer.new()
	_left_info.name = "LeftInfo"
	_left_info.anchor_left = 0.0
	_left_info.anchor_top = 0.74
	_left_info.anchor_right = 0.44
	_left_info.anchor_bottom = 1.0
	_left_info.offset_left = 16.0
	_left_info.offset_top = 4.0
	_left_info.offset_right = -16.0
	_left_info.offset_bottom = -12.0
	_left_info.add_theme_constant_override("separation", _theme_config.list_separation)
	_left_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_info)

	# Rechte Spalte: Bauplätze + Gebäude + planetare Forschung.
	var scroll := ScrollContainer.new()
	scroll.name = "BuildSlotsScroll"
	_build_scroll = scroll
	scroll.anchor_left = 0.48
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 8.0
	scroll.offset_top = 8.0
	scroll.offset_right = -8.0
	scroll.offset_bottom = -8.0
	scroll.add_theme_stylebox_override("panel", _theme_config.make_style_box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0))
	add_child(scroll)

	_slot_content = VBoxContainer.new()
	_slot_content.name = "BuildSlotContent"
	_slot_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_content.add_theme_constant_override("separation", _theme_config.content_separation)
	scroll.add_child(_slot_content)

# ── Eigene Planeten ────────────────────────────────────────────────────

func _collect_own_planets() -> void:
	_own_planets.clear()
	if _state == null:
		return
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("planets"):
			var candidate: Planet = node as Planet
			if candidate == null:
				continue
			if _is_own_planet(candidate):
				_own_planets.append(candidate)
	# Fallback: die übergebene Auswahl zählt als eigener Planet.
	if _own_planets.is_empty() and _planet != null and is_instance_valid(_planet) and _is_own_planet(_planet):
		_own_planets.append(_planet)

func _is_own_planet(planet: Planet) -> bool:
	if planet == null or _state == null:
		return false
	return _state.faction_of(planet.planet_id) == GameState.FACTION_PLAYER

func _rebuild_selector() -> void:
	if _planets_list == null:
		return
	for child in _planets_list.get_children():
		_planets_list.remove_child(child)
		child.queue_free()
	_planets_list.add_child(UIBaseUtils.make_label("EIGENE PLANETEN (%d)" % _own_planets.size(), _theme_config.heading_text_color, _theme_config.section_font_size))
	if _own_planets.is_empty():
		_planets_list.add_child(UIBaseUtils.make_label("Noch keine eigenen Planeten.", _theme_config.muted_text_color, _theme_config.small_font_size))
		return
	for planet in _own_planets:
		if planet == null:
			continue
		var active: bool = _planet != null and is_instance_valid(_planet) and _planet.planet_id == planet.planet_id
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.text = _planet_selector_text(planet)
		row.tooltip_text = _planet_selector_text(planet)
		row.add_theme_font_size_override("font_size", _theme_config.small_font_size)
		if active:
			row.add_theme_color_override("font_color", _theme_config.branch_tech_color)
			row.add_theme_color_override("font_hover_color", _theme_config.branch_tech_color.lightened(0.15))
		else:
			row.add_theme_color_override("font_color", _theme_config.secondary_text_color)
			row.add_theme_color_override("font_hover_color", _theme_config.accent_text_color)
		row.add_theme_stylebox_override("normal", UIBaseUtils.style_box(_theme_config, _theme_config.card_background if active else Color(0, 0, 0, 0), _theme_config.branch_tech_color.darkened(0.4) if active else Color.TRANSPARENT, 1, _theme_config.panel_corner_radius))
		row.add_theme_stylebox_override("hover", UIBaseUtils.style_box(_theme_config, _theme_config.input_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
		row.pressed.connect(_select_planet.bind(planet))
		_planets_list.add_child(row)

func _planet_selector_text(planet: Planet) -> String:
	if planet == null or _state == null:
		return ""
	var planet_id: StringName = planet.planet_id
	var hangar_occupied: int = int(_state.get_ship_build_jobs(planet_id).size() + _state.get_ship_assemblies(planet_id).size())
	var hangar_total: int = planet.get_build_slot_count()
	var building_jobs: int = _count_building_jobs(planet_id)
	var upgrades: int = _state.get_planet_upgrades(planet_id).size()
	var parts: Array[String] = [UIBaseUtils.planet_display_name(planet), "%d/%d Hangar" % [hangar_occupied, hangar_total], "%d Gebäude" % upgrades]
	if building_jobs > 0:
		parts.append("⟳ %d Bau" % building_jobs)
	return " · ".join(parts)

func _count_building_jobs(planet_id: StringName) -> int:
	if _state == null or not _state.has_method("upgrade_build_in_progress"):
		return 0
	if not _state.upgrade_build_in_progress(planet_id):
		return 0
	var count := 0
	for upgrade in _upgrade_catalog.upgrades:
		if upgrade != null and _state.upgrade_build_in_progress(planet_id, upgrade.id):
			count += 1
	return count

func _select_planet(planet: Planet) -> void:
	if planet == null:
		return
	_planet = planet
	_rebuild_selector()
	_rebuild_all()
	queue_redraw()

# ── Inhalt (rechte Spalte) ─────────────────────────────────────────────

func _rebuild_all() -> void:
	_build_bars.clear()
	_build_labels.clear()
	_refresh_left_info()
	_rebuild_slots()

func _refresh_left_info() -> void:
	if _left_info == null:
		return
	for child in _left_info.get_children():
		_left_info.remove_child(child)
		child.queue_free()
	if _planet == null or not is_instance_valid(_planet) or _state == null:
		return
	var name_text: String = UIBaseUtils.planet_display_name(_planet)
	_left_info.add_child(UIBaseUtils.make_label(name_text.to_upper(), _theme_config.heading_text_color, _theme_config.panel_title_font_size))
	var faction_id: StringName = _state.faction_of(_planet.planet_id)
	var faction_str: String = UIBaseUtils.faction_display_name(faction_id)
	_left_info.add_child(UIBaseUtils.make_label("Status: %s" % faction_str, DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction_id), _theme_config.body_font_size))
	var resource_id: StringName = _state.resource_of(_planet.planet_id) if _state.is_known(_planet.planet_id, GameState.FACTION_PLAYER) else &""
	var resource_text: String = UIBaseUtils.resource_display_name(resource_id) if not String(resource_id).is_empty() else "Unbekannt (Forschungsschiff benötigt)"
	_left_info.add_child(UIBaseUtils.make_label("Produktion: %s" % resource_text, _theme_config.resource_color(resource_id), _theme_config.body_font_size))
	_left_info.add_child(UIBaseUtils.make_label(
		"Bauplätze: %d  ·  Perimeter: %d  ·  Reichweite: %.0f px" % [_planet.get_build_slot_count(), _planet.get_perimeter_slots(), _planet.get_defense_range()],
		_theme_config.secondary_text_color,
		_theme_config.small_font_size
	))
	var workers: int = int(_planet.get("worker_count")) if _planet.get("worker_count") != null else 0
	_left_info.add_child(UIBaseUtils.make_label("Einheiten auf dem Planeten: %d" % workers, _theme_config.secondary_text_color, _theme_config.small_font_size))

func _rebuild_slots() -> void:
	if _slot_content == null:
		return
	for child in _slot_content.get_children():
		_slot_content.remove_child(child)
		child.queue_free()
	if _planet == null or not is_instance_valid(_planet) or _state == null or _upgrade_catalog == null:
		return
	var planet_id: StringName = _planet.planet_id

	_slot_content.add_child(UIBaseUtils.make_label("BAUPLÄTZE — HANGAR", _theme_config.heading_text_color, _theme_config.section_font_size))
	_slot_content.add_child(UIBaseUtils.make_separator())
	_slot_content.add_child(_build_hangar_strip(planet_id))

	_slot_content.add_child(UIBaseUtils.make_separator())
	_slot_content.add_child(UIBaseUtils.make_label("GEBÄUDE", _theme_config.heading_text_color, _theme_config.section_font_size))
	var unlocked: Array[StringName] = _state.get_planet_upgrades(planet_id)
	var is_owned: bool = _state.is_owned_by(planet_id, GameState.FACTION_PLAYER)
	var branch_order: Array[StringName] = [&"economy", &"military", &"tech", &"infrastructure"]
	for branch in branch_order:
		var branch_upgrades: Array[PlanetUpgradeDefinition] = _upgrade_catalog.get_upgrades_for_branch(branch)
		if branch_upgrades.is_empty():
			continue
		_slot_content.add_child(UIBaseUtils.make_label(String(branch).to_upper(), _theme_config.branch_color(branch), _theme_config.section_font_size))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", _theme_config.card_padding)
		flow.add_theme_constant_override("v_separation", _theme_config.card_padding)
		for upgrade in branch_upgrades:
			if upgrade == null:
				continue
			flow.add_child(_magnet_tile(planet_id, upgrade, unlocked.has(upgrade.id), is_owned))
		_slot_content.add_child(flow)

	_slot_content.add_child(UIBaseUtils.make_separator())
	_slot_content.add_child(UIBaseUtils.make_label("PLANETARE FORSCHUNG", _theme_config.heading_text_color, _theme_config.section_font_size))
	_slot_content.add_child(UIBaseUtils.make_label("Per-Planeten-Technologien (z. B. Survey, Extraction) — gelten nur für diese Welt.", _theme_config.muted_text_color, _theme_config.small_font_size))
	var planet_technologies: Array[TechnologyDefinition] = _technology_catalog.for_category(TechnologyDefinition.CATEGORY_PLANET)
	if planet_technologies.is_empty():
		_slot_content.add_child(UIBaseUtils.make_label("Keine planetaren Technologien definiert.", _theme_config.muted_text_color, _theme_config.small_font_size))
	else:
		for technology in planet_technologies:
			_slot_content.add_child(_planet_research_row(planet_id, technology, is_owned))

func _build_hangar_strip(planet_id: StringName) -> Control:
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", _theme_config.list_separation)
	var jobs: Dictionary = _state.get_ship_build_jobs(planet_id)
	var assemblies: Dictionary = _state.get_ship_assemblies(planet_id)
	var occupied: int = jobs.size() + assemblies.size()
	var total: int = _planet.get_build_slot_count()
	var building_jobs: int = _count_building_jobs(planet_id)
	var summary_parts: Array[String] = ["%d / %d Hangarplätze belegt" % [occupied, total]]
	if building_jobs > 0:
		summary_parts.append("⟳ %d Gebäude im Bau" % building_jobs)
	strip.add_child(UIBaseUtils.make_label(" · ".join(summary_parts), _theme_config.secondary_text_color, _theme_config.small_font_size))

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 6)
	for index in total:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(26.0, 26.0)
		var free: bool = index >= occupied
		var cell_bg: Color = _theme_config.input_background if free else _theme_config.branch_tech_color.darkened(0.35)
		cell.add_theme_stylebox_override("panel", UIBaseUtils.style_box(_theme_config, cell_bg, _theme_config.panel_border, 1, 4))
		cell.tooltip_text = "Hangarplatz %d: %s" % [index + 1, "frei" if free else "belegt (Schiff/Montage)"]
		cells.add_child(cell)
	strip.add_child(cells)
	return strip

func _magnet_tile(planet_id: StringName, upgrade: PlanetUpgradeDefinition, is_unlocked: bool, is_owned: bool) -> Control:
	var build_in_progress: bool = _state.upgrade_build_in_progress(planet_id, upgrade.id)
	var can_buy: bool = is_owned and _state.can_purchase_upgrade(planet_id, upgrade.id, _upgrade_catalog, int(_planet.get("worker_count")))
	var state_id: StringName = UIStatusUtils.upgrade_state(is_owned, is_unlocked, build_in_progress, can_buy)
	var accent: Color = UIStatusUtils.state_color(state_id, _theme_config)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(210.0, 0.0)
	tile.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.card_background, accent.darkened(0.35), 1, _theme_config.panel_corner_radius)
	)
	tile.tooltip_text = upgrade.description
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", _theme_config.list_separation)
	content.add_child(UIBaseUtils.make_label(upgrade.display_name, accent, _theme_config.body_font_size, false))
	var state_label := UIBaseUtils.make_label(_state_text(planet_id, upgrade, is_unlocked, build_in_progress, can_buy), accent, _theme_config.small_font_size, false)
	if build_in_progress:
		state_label.set_meta("planet_id", planet_id)
		state_label.set_meta("upgrade_id", upgrade.id)
		_build_labels.append(state_label)
	content.add_child(state_label)

	var effect_text := UIStatusUtils.trait_effect_summary(upgrade.trait_definition)
	if not effect_text.is_empty():
		content.add_child(UIBaseUtils.make_label(effect_text, _theme_config.muted_text_color, _theme_config.small_font_size, false))
	var required_tech: String = UIStatusUtils.required_tech_status(upgrade.required_technology_id, _state, _technology_catalog)
	if not required_tech.is_empty():
		var tech_color: Color = UIStatusUtils.state_color(UIStatusUtils.research_state(GameState.FACTION_PLAYER, _technology_catalog.resolve(upgrade.required_technology_id), _state, _technology_catalog), _theme_config)
		content.add_child(UIBaseUtils.make_label(required_tech, tech_color, _theme_config.small_font_size, false))

	if build_in_progress:
		var remaining: float = _state.upgrade_build_remaining(planet_id, upgrade.id)
		var progress := ProgressBar.new()
		progress.name = "UpgradeBuildProgress"
		progress.custom_minimum_size = Vector2(0.0, 6.0)
		progress.min_value = 0.0
		progress.max_value = maxf(upgrade.build_time, 1.0)
		progress.value = clampf(upgrade.build_time - remaining, 0.0, progress.max_value)
		progress.show_percentage = false
		progress.tooltip_text = "Baufortschritt"
		progress.set_meta("planet_id", planet_id)
		progress.set_meta("upgrade_id", upgrade.id)
		progress.set_meta("total_time", maxf(upgrade.build_time, 1.0))
		_build_bars.append(progress)
		content.add_child(progress)

		var abort := Button.new()
		abort.text = "ABBRECHEN"
		abort.focus_mode = Control.FOCUS_NONE
		abort.add_theme_font_size_override("font_size", _theme_config.small_font_size)
		abort.tooltip_text = "Bau abbrechen und Kosten zurückerhalten"
		abort.pressed.connect(_abort_build.bind(planet_id, upgrade.id))
		content.add_child(abort)
	elif not is_unlocked:
		var buy := Button.new()
		buy.text = "BAUEN"
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = not can_buy
		buy.tooltip_text = _buy_tooltip(upgrade, is_owned, can_buy, state_id)
		buy.pressed.connect(_buy_upgrade.bind(planet_id, upgrade.id))
		content.add_child(buy)

	tile.add_child(content)
	return tile

func _state_text(planet_id: StringName, upgrade: PlanetUpgradeDefinition, is_unlocked: bool, build_in_progress: bool, can_buy: bool) -> String:
	if is_unlocked:
		return "✓ GEBÄUDE AKTIV"
	if build_in_progress:
		var remaining: float = _state.upgrade_build_remaining(planet_id, upgrade.id)
		return "⟳ IM BAU · %s" % UIStatusUtils.build_progress_text(remaining)
	if not can_buy:
		var reason := _locked_reason(upgrade)
		if not reason.is_empty():
			return "✗ GESPERRT · %s" % reason
		return "✗ GESPERRT"
	return "● BAUBAR · %s" % UIBaseUtils.cost_text(upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost)

func _locked_reason(upgrade: PlanetUpgradeDefinition) -> String:
	if _planet == null or _state == null:
		return ""
	if not _state.is_owned_by(_planet.planet_id, GameState.FACTION_PLAYER):
		return "kein eigener Planet"
	var required_tech_status: String = UIStatusUtils.required_tech_status(upgrade.required_technology_id, _state, _technology_catalog)
	if not required_tech_status.is_empty():
		return "Forschung fehlt"
	return "Ressourcen fehlen"

func _buy_tooltip(upgrade: PlanetUpgradeDefinition, is_owned: bool, _can_buy: bool, state_id: StringName) -> String:
	if not is_owned:
		return "Bauen erfordert einen eigenen Planeten."
	if state_id == UIStatusUtils.STATE_LOCKED:
		var missing_tech: String = UIStatusUtils.required_tech_status(upgrade.required_technology_id, _state, _technology_catalog)
		if not missing_tech.is_empty():
			return missing_tech
		return "Kosten oder Voraussetzungen fehlen."
	return UIBaseUtils.cost_text(upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost)

func _buy_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	if _state == null or _planet == null or not is_instance_valid(_planet):
		return
	var upgrade: PlanetUpgradeDefinition = _upgrade_catalog.resolve(upgrade_id)
	if upgrade == null:
		return
	var available_workers: int = int(_planet.get("worker_count"))
	if not _state.purchase_upgrade(planet_id, upgrade_id, _upgrade_catalog, available_workers):
		return
	_rebuild_all()

func _abort_build(planet_id: StringName, upgrade_id: StringName) -> void:
	if _state == null:
		return
	if _state.abort_upgrade_build(planet_id, upgrade_id):
		_rebuild_all()

func _planet_research_row(planet_id: StringName, technology: TechnologyDefinition, own_planet: bool) -> Control:
	var researched: bool = _state.has_planet_technology(planet_id, technology.id)
	var can_research: bool = own_planet and _state.can_research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology.id, _technology_catalog)
	var state_id: StringName = UIStatusUtils.planet_research_state(own_planet, researched, false, can_research)
	var accent: Color = UIStatusUtils.state_color(state_id, _theme_config)
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.card_background, accent.darkened(0.35), 1, _theme_config.panel_corner_radius)
	)
	row.tooltip_text = technology.description
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _theme_config.card_padding)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIBaseUtils.make_label(technology.display_name, _theme_config.heading_text_color, _theme_config.body_font_size))
	box.add_child(UIBaseUtils.make_label(technology.description, _theme_config.muted_text_color, _theme_config.small_font_size))
	var status_text: String
	if researched:
		status_text = "✓ FÜR DIESEN PLANETEN AKTIV"
	elif not own_planet:
		status_text = "✗ GESPERRT (nur eigene Planeten)"
	elif can_research:
		status_text = "● LERNBAR · %s" % UIBaseUtils.technology_cost_text(technology, _state)
	else:
		status_text = "✗ NOCH NICHT LERNBAR · %s" % UIBaseUtils.technology_cost_text(technology, _state)
	box.add_child(UIBaseUtils.make_label(status_text, accent, _theme_config.small_font_size))
	var research_button := Button.new()
	research_button.text = "FORSCHEN"
	research_button.focus_mode = Control.FOCUS_NONE
	research_button.disabled = researched or not can_research
	if not can_research:
		research_button.tooltip_text = "Nur auf eigenen Planeten forschbar; Kosten prüfen."
	if not researched and can_research:
		research_button.pressed.connect(_research_planet_tech.bind(planet_id, technology.id))
	content.add_child(box)
	content.add_child(research_button)
	row.add_child(content)
	return row

func _research_planet_tech(planet_id: StringName, technology_id: StringName) -> void:
	if _state == null:
		return
	if _state.research_planet_technology(GameState.FACTION_PLAYER, planet_id, technology_id, _technology_catalog):
		_rebuild_all()

# ── Live-Refresh ───────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	queue_redraw()
	_refresh_accumulator += delta
	if _refresh_accumulator >= REFRESH_INTERVAL:
		_refresh_accumulator = 0.0
		_update_live_countdowns()

func _update_live_countdowns() -> void:
	if _state == null or not is_visible_in_tree():
		return
	var needs_rebuild := false
	for bar in _build_bars:
		if bar == null or not is_instance_valid(bar):
			continue
		var planet_id: StringName = bar.get_meta("planet_id", &"") as StringName
		var upgrade_id: StringName = bar.get_meta("upgrade_id", &"") as StringName
		if not _state.upgrade_build_in_progress(planet_id, upgrade_id):
			needs_rebuild = true
			continue
		var remaining: float = _state.upgrade_build_remaining(planet_id, upgrade_id)
		var total_time: float = float(bar.get_meta("total_time", 1.0))
		bar.value = clampf(total_time - remaining, 0.0, bar.max_value)
	if needs_rebuild:
		call_deferred("_rebuild_all")
		return
	# Statuszeilen in den Tiles aktualisieren (Restzeit).
	for label in _build_labels:
		if label == null or not is_instance_valid(label):
			continue
		var planet_id: StringName = label.get_meta("planet_id", &"") as StringName
		var upgrade_id: StringName = label.get_meta("upgrade_id", &"") as StringName
		if _state.upgrade_build_in_progress(planet_id, upgrade_id):
			var remaining: float = _state.upgrade_build_remaining(planet_id, upgrade_id)
			label.text = "⟳ IM BAU · %s" % UIStatusUtils.build_progress_text(remaining)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var left_width := size.x * 0.44
	var center := Vector2(left_width * 0.5, size.y * 0.34)
	var radius := minf(left_width * 0.40, size.y * 0.28)
	if radius <= 4.0:
		return
	draw_circle(center, radius, Color(0.26, 0.32, 0.42))
	draw_arc(center, radius, 0.0, TAU, 72, _theme_config.panel_border, 2.0, true)
	var ring_colors: Array[Color] = [
		_theme_config.branch_tech_color,
		_theme_config.branch_economy_color,
		_theme_config.branch_military_color,
	]
	for index in range(ring_colors.size()):
		var ring_radius: float = radius * (1.35 + 0.24 * float(index))
		var start_angle: float = _phase + float(index) * 1.1
		draw_arc(center, ring_radius, start_angle, start_angle + 2.3, 48, ring_colors[index], 1.6, true)
	if _planet != null and is_instance_valid(_planet):
		var faction_tint: Color = DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", _planet.get_faction())
		draw_arc(center, radius + 7.0, 0.0, TAU, 72, Color(faction_tint.r, faction_tint.g, faction_tint.b, 0.5), 3.0, true)
