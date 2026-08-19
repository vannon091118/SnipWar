class_name PlanetPanel
extends PanelContainer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")

signal destination_selected(index: int)
signal mission_selected(mission_type: StringName)
signal amount_changed(value: float)
signal send_pressed()
signal layout_requested()
signal clear_selection_pressed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _upgrade_catalog: PlanetUpgradeCatalog = DEFAULT_UPGRADE_CATALOG
var _count_labels: Dictionary = {}
var _current_active_planet: Node2D
var _branch_expanded: Dictionary = {
	&"economy": true,
	&"military": false,
	&"tech": false,
	&"infrastructure": false
}

@onready var _heading_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/HeadingLabel")
@onready var _selected_planet_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/SelectedPlanetLabel")
@onready var _faction_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/FactionLabel")
@onready var _resource_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/ResourceLabel")
@onready var _selected_count_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/SelectedCountLabel")
@onready var _build_space_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/BuildSpaceLabel")
@onready var _destination_heading: Label = get_node_or_null("MarginContainer/PanelScroll/Content/DestinationHeading")
@onready var _destination_option: OptionButton = get_node_or_null("MarginContainer/PanelScroll/Content/DestinationSelect")
@onready var _mission_heading: Label = get_node_or_null("MarginContainer/PanelScroll/Content/MissionHeading")
@onready var _mission_option: OptionButton = get_node_or_null("MarginContainer/PanelScroll/Content/MissionSelect")
@onready var _send_heading: Label = get_node_or_null("MarginContainer/PanelScroll/Content/SendHeading")
@onready var _amount_slider: HSlider = get_node_or_null("MarginContainer/PanelScroll/Content/AmountSlider")
@onready var _preview_label: Label = get_node_or_null("MarginContainer/PanelScroll/Content/PreviewLabel")
@onready var _send_button: Button = get_node_or_null("MarginContainer/PanelScroll/Content/SendButton")
@onready var _upgrade_heading: Label = get_node_or_null("MarginContainer/PanelScroll/Content/UpgradeHeading")
@onready var _upgrade_list: VBoxContainer = get_node_or_null("MarginContainer/PanelScroll/Content/UpgradeScroll/UpgradeList")
@onready var _units_heading: Label = get_node_or_null("MarginContainer/PanelScroll/Content/UnitsHeading")
@onready var _count_list: VBoxContainer = get_node_or_null("MarginContainer/PanelScroll/Content/ScrollContainer/CountList")
@onready var _margin: MarginContainer = get_node_or_null("MarginContainer")
@onready var _content: VBoxContainer = get_node_or_null("MarginContainer/PanelScroll/Content")

var _selection_count_label: Label = null
var _selection_overview_box: VBoxContainer = null
var _selection_clear_button: Button = null
var _selection_total_label: Label = null

func setup(theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ensure_node_references()
	_apply_theme()
	_setup_missions()
	_connect_internal_signals()
	_connect_game_state_signals()

func _ensure_node_references() -> void:
	if _heading_label == null:
		_heading_label = get_node_or_null("MarginContainer/PanelScroll/Content/HeadingLabel")
	if _selected_planet_label == null:
		_selected_planet_label = get_node_or_null("MarginContainer/PanelScroll/Content/SelectedPlanetLabel")
	if _faction_label == null:
		_faction_label = get_node_or_null("MarginContainer/PanelScroll/Content/FactionLabel")
	if _resource_label == null:
		_resource_label = get_node_or_null("MarginContainer/PanelScroll/Content/ResourceLabel")
	if _selected_count_label == null:
		_selected_count_label = get_node_or_null("MarginContainer/PanelScroll/Content/SelectedCountLabel")
	if _build_space_label == null:
		_build_space_label = get_node_or_null("MarginContainer/PanelScroll/Content/BuildSpaceLabel")
	if _destination_heading == null:
		_destination_heading = get_node_or_null("MarginContainer/PanelScroll/Content/DestinationHeading")
	if _destination_option == null:
		_destination_option = get_node_or_null("MarginContainer/PanelScroll/Content/DestinationSelect")
	if _mission_heading == null:
		_mission_heading = get_node_or_null("MarginContainer/PanelScroll/Content/MissionHeading")
	if _mission_option == null:
		_mission_option = get_node_or_null("MarginContainer/PanelScroll/Content/MissionSelect")
	if _send_heading == null:
		_send_heading = get_node_or_null("MarginContainer/PanelScroll/Content/SendHeading")
	if _amount_slider == null:
		_amount_slider = get_node_or_null("MarginContainer/PanelScroll/Content/AmountSlider")
	if _preview_label == null:
		_preview_label = get_node_or_null("MarginContainer/PanelScroll/Content/PreviewLabel")
	if _send_button == null:
		_send_button = get_node_or_null("MarginContainer/PanelScroll/Content/SendButton")
	if _upgrade_heading == null:
		_upgrade_heading = get_node_or_null("MarginContainer/PanelScroll/Content/UpgradeHeading")
	if _upgrade_list == null:
		_upgrade_list = get_node_or_null("MarginContainer/PanelScroll/Content/UpgradeScroll/UpgradeList")
	if _units_heading == null:
		_units_heading = get_node_or_null("MarginContainer/PanelScroll/Content/UnitsHeading")
	if _count_list == null:
		_count_list = get_node_or_null("MarginContainer/PanelScroll/Content/ScrollContainer/CountList")
	if _margin == null:
		_margin = get_node_or_null("MarginContainer")
	if _content == null:
		_content = get_node_or_null("MarginContainer/PanelScroll/Content")

func _setup_missions() -> void:
	if _mission_option == null:
		return
	_mission_option.clear()
	_mission_option.add_item("Militärverband (K/M/L)", 0)
	_mission_option.set_item_metadata(0, &"military")
	_mission_option.add_item("Frachtschiff (Ressourcen-Transfer)", 1)
	_mission_option.set_item_metadata(1, &"cargo")
	_mission_option.add_item("Kolonieschiff (Expansions-Besiedlung)", 2)
	_mission_option.set_item_metadata(2, &"colony")
	_mission_option.add_item("Sammeltrupp (erste Einnahmen)", 3)
	_mission_option.set_item_metadata(3, &"collect")
	_mission_option.select(0)

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
	# Affordability only concerns the player faction; skip CPU ticks and rebuild
	# the (hidden) upgrade list only while the panel is open.
	if faction != GameState.FACTION_PLAYER:
		return
	if is_instance_valid(_current_active_planet) and visible:
		_refresh_upgrade_list(_current_active_planet)

func _on_planet_upgraded(planet_id: StringName, _upgrade_id: StringName) -> void:
	if is_instance_valid(_current_active_planet) and visible and _current_active_planet.get("planet_id") == planet_id:
		_refresh_upgrade_list(_current_active_planet)

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	if is_instance_valid(_current_active_planet) and visible:
		_refresh_upgrade_list(_current_active_planet)

func _apply_theme() -> void:
	add_theme_stylebox_override("panel", _style_box(_theme_config.panel_background, _theme_config.panel_border, _theme_config.panel_border_width, _theme_config.panel_corner_radius))
	if _margin != null:
		_margin.add_theme_constant_override("margin_left", _theme_config.content_margin_left)
		_margin.add_theme_constant_override("margin_top", _theme_config.content_margin_top)
		_margin.add_theme_constant_override("margin_right", _theme_config.content_margin_right)
		_margin.add_theme_constant_override("margin_bottom", _theme_config.content_margin_bottom)
	if _content != null:
		_content.add_theme_constant_override("separation", _theme_config.content_separation)
	if _heading_label != null:
		_heading_label.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
		_heading_label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	if _selected_planet_label != null:
		_selected_planet_label.add_theme_font_size_override("font_size", _theme_config.panel_title_font_size)
		_selected_planet_label.add_theme_color_override("font_color", _theme_config.selected_planet_text_color)
	if _faction_label != null:
		_faction_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
	if _resource_label != null:
		_resource_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
	if _selected_count_label != null:
		_selected_count_label.add_theme_font_size_override("font_size", _theme_config.selected_count_font_size)
		_selected_count_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)
	if _build_space_label != null:
		_build_space_label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
		_build_space_label.add_theme_color_override("font_color", _theme_config.secondary_text_color)
	var headings: Array[Label] = [_destination_heading, _mission_heading, _send_heading, _upgrade_heading, _units_heading]
	for heading in headings:
		if heading != null:
			heading.add_theme_font_size_override("font_size", _theme_config.section_font_size)
			heading.add_theme_color_override("font_color", _theme_config.heading_text_color)
	var input_controls: Array[Control] = [_destination_option, _mission_option]
	for input_control in input_controls:
		if input_control != null:
			input_control.add_theme_font_size_override("font_size", _theme_config.body_font_size)
			input_control.add_theme_stylebox_override("normal", _style_box(_theme_config.input_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
			input_control.add_theme_stylebox_override("hover", _style_box(_theme_config.input_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
			input_control.add_theme_stylebox_override("pressed", _style_box(_theme_config.input_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
	if _preview_label != null:
		_preview_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
		_preview_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)
	if _send_button != null:
		_send_button.add_theme_font_size_override("font_size", _theme_config.body_font_size)
		_send_button.add_theme_stylebox_override("normal", _style_box(_theme_config.button_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
		_send_button.add_theme_stylebox_override("hover", _style_box(_theme_config.button_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
		_send_button.add_theme_stylebox_override("disabled", _style_box(_theme_config.button_disabled_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
	if _upgrade_list != null:
		_upgrade_list.add_theme_constant_override("separation", _theme_config.list_separation)
	if _count_list != null:
		_count_list.add_theme_constant_override("separation", _theme_config.list_separation)

func _style_box(background: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 0) -> StyleBoxFlat:
	return UIBaseUtils.style_box(_theme_config, background, border, border_width, radius)

func _connect_internal_signals() -> void:
	if _destination_option != null and not _destination_option.item_selected.is_connected(_on_destination_selected):
		_destination_option.item_selected.connect(_on_destination_selected)
	if _mission_option != null and not _mission_option.item_selected.is_connected(_on_mission_selected):
		_mission_option.item_selected.connect(_on_mission_selected)
	if _amount_slider != null and not _amount_slider.value_changed.is_connected(_on_amount_changed):
		_amount_slider.value_changed.connect(_on_amount_changed)
	if _send_button != null and not _send_button.pressed.is_connected(_on_send_pressed):
		_send_button.pressed.connect(_on_send_pressed)

func populate_units(planets: Array[Node2D]) -> void:
	if _count_list == null:
		return
	for child in _count_list.get_children():
		child.queue_free()
	_count_labels.clear()

	for planet in planets:
		var count_label := Label.new()
		count_label.text = _count_text(planet)
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_label.add_theme_color_override("font_color", _theme_config.accent_text_color)
		_count_labels[planet] = count_label
		_count_list.add_child(count_label)

func set_destinations(destinations: Array[Node2D], default_destination: Node2D) -> void:
	_ensure_node_references()
	_destination_option.clear()
	_destination_option.disabled = destinations.is_empty()
	var state: Node = get_tree().root.get_node_or_null("GameState")
	var idx := 0
	for destination in destinations:
		var d_name: String = destination.name
		if state != null and destination.get("planet_id") != null:
			if not state.is_known(destination.get("planet_id"), GameState.FACTION_PLAYER):
				d_name = "??? (Unbekannt)"
		_destination_option.add_item(d_name)
		_destination_option.set_item_metadata(idx, destination.name)
		idx += 1

	if default_destination != null:
		var target_idx := destinations.find(default_destination)
		if target_idx >= 0:
			_destination_option.select(target_idx)

	set_preview("Kein Ziel verfügbar" if destinations.is_empty() else _preview_label.text)

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	_ensure_node_references()
	_current_active_planet = planet

	var state: Node = get_tree().root.get_node_or_null("GameState")
	var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
	var is_known: bool = state != null and state.is_known(planet_id, GameState.FACTION_PLAYER)

	_selected_planet_label.text = planet.name.to_upper() if is_known else "??? (UNBEKANNT)"

	if state != null:
		var faction_id: StringName = state.faction_of(planet_id)
		var faction_str: String = "Spieler [A]" if faction_id == &"a" else ("CPU [B]" if faction_id == &"b" else "Neutral")
		if _faction_label != null:
			_faction_label.text = "Besitzer: %s" % faction_str
			_faction_label.add_theme_color_override("font_color", DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction_id))

		var resource_id: StringName = state.resource_of(planet_id) if state.is_known(planet_id, GameState.FACTION_PLAYER) else &""
		var resource_name: String = String(resource_id).capitalize() if not String(resource_id).is_empty() else "Unbekannt (Scout benötigt)"
		var extra_info := ""
		if state.has_planet_upgrade(planet_id, &"refinery"):
			extra_info = " ⚗️"
		if _resource_label != null:
			_resource_label.text = "Ressource: %s%s" % [resource_name, extra_info]
			_resource_label.add_theme_color_override("font_color", _theme_config.resource_color(resource_id))
	if _build_space_label != null:
		var selected_planet: Planet = planet as Planet
		var build_slots: int = selected_planet.get_build_slot_count() if selected_planet != null else 0
		var perimeter_slots: int = selected_planet.get_perimeter_slots() if selected_planet != null and selected_planet.has_method("get_perimeter_slots") else build_slots
		var defense_range: float = selected_planet.get_defense_range() if selected_planet != null and selected_planet.has_method("get_defense_range") else 150.0
		_build_space_label.text = "Bauplätze: %d  ·  Perimeter: %d  ·  Reichweite: %.0f px" % [build_slots, perimeter_slots, defense_range]

	set_destinations(destinations, default_destination)

	_refresh_upgrade_list(planet)
	layout_requested.emit()

func _refresh_upgrade_list(planet: Node2D) -> void:
	if _build_space_label != null and is_instance_valid(planet):
		var selected_planet: Planet = planet as Planet
		var build_slots: int = selected_planet.get_build_slot_count() if selected_planet != null else 0
		var perimeter_slots: int = selected_planet.get_perimeter_slots() if selected_planet != null and selected_planet.has_method("get_perimeter_slots") else build_slots
		var defense_range: float = selected_planet.get_defense_range() if selected_planet != null and selected_planet.has_method("get_defense_range") else 150.0
		_build_space_label.text = "Bauplätze: %d  ·  Perimeter-Slots: %d  ·  Reichweite: %.0f px" % [build_slots, perimeter_slots, defense_range]

	if _upgrade_list == null:
		return
	for child in _upgrade_list.get_children():
		_upgrade_list.remove_child(child)
		child.queue_free()

	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null or _upgrade_catalog == null or not is_instance_valid(planet):
		return

	var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
	var unlocked_upgrades: Array[StringName] = state.get_planet_upgrades(planet_id)
	var is_player_owned: bool = state.owns(planet_id, &"a")
	var branch_order: Array[StringName] = [&"economy", &"military", &"tech", &"infrastructure"]
	var branch_titles: Dictionary = {
		&"economy": "WIRTSCHAFT",
		&"military": "MILITÄR",
		&"tech": "TECHNOLOGIE",
		&"infrastructure": "INFRASTRUKTUR"
	}

	for branch in branch_order:
		var branch_upgrades: Array[PlanetUpgradeDefinition] = _upgrade_catalog.get_upgrades_for_branch(branch)
		if branch_upgrades.is_empty():
			continue
		var expanded: bool = bool(_branch_expanded.get(branch, false))
		var branch_button := Button.new()
		branch_button.text = ("▾  " if expanded else "▸  ") + String(branch_titles.get(branch, String(branch).capitalize()))
		branch_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		branch_button.flat = true
		branch_button.focus_mode = Control.FOCUS_NONE
		branch_button.custom_minimum_size = Vector2(0.0, _theme_config.section_row_height)
		branch_button.add_theme_font_size_override("font_size", _theme_config.section_font_size)
		branch_button.add_theme_color_override("font_color", _theme_config.branch_color(branch))
		branch_button.add_theme_color_override("font_hover_color", _theme_config.branch_color(branch).lightened(0.15))
		branch_button.pressed.connect(Callable(self, "_on_branch_toggled").bind(branch))
		_upgrade_list.add_child(branch_button)

		if not expanded:
			continue
		for upgrade in branch_upgrades:
			if upgrade == null:
				continue
			var is_unlocked: bool = unlocked_upgrades.has(upgrade.id)
			var can_buy: bool = is_player_owned and state.can_purchase_upgrade(planet_id, upgrade.id, _upgrade_catalog, int(planet.get("worker_count")))
			_upgrade_list.add_child(_create_upgrade_row(planet_id, upgrade, is_unlocked, can_buy))

func _on_branch_toggled(branch: StringName) -> void:
	_branch_expanded[branch] = not bool(_branch_expanded.get(branch, false))
	if is_instance_valid(_current_active_planet):
		_refresh_upgrade_list(_current_active_planet)
		layout_requested.emit()

func _create_upgrade_row(planet_id: StringName, upgrade: PlanetUpgradeDefinition, is_unlocked: bool, can_buy: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _style_box(_theme_config.card_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
	row.tooltip_text = upgrade.description

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _theme_config.card_padding)
	margin.add_theme_constant_override("margin_top", _theme_config.card_padding)
	margin.add_theme_constant_override("margin_right", _theme_config.card_padding)
	margin.add_theme_constant_override("margin_bottom", _theme_config.card_padding)
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _theme_config.content_separation)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = upgrade.display_name
	name_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
	name_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color if is_unlocked else _theme_config.accent_text_color)
	info.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = _upgrade_cost_text(upgrade, is_unlocked)
	var trait_text := _upgrade_trait_text(upgrade)
	if not trait_text.is_empty():
		detail_label.text += "\n" + trait_text
	if not String(upgrade.required_technology_id).is_empty():
		var required_technology: TechnologyDefinition = DEFAULT_TECHNOLOGY_CATALOG.resolve(upgrade.required_technology_id)
		detail_label.text += "\nForschung erforderlich: %s" % (required_technology.display_name if required_technology != null else String(upgrade.required_technology_id))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	detail_label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	info.add_child(detail_label)
	content.add_child(info)

	if not is_unlocked:
		var buy_button := Button.new()
		buy_button.text = "BAUEN"
		buy_button.disabled = not can_buy
		buy_button.focus_mode = Control.FOCUS_NONE
		buy_button.custom_minimum_size = Vector2(_theme_config.upgrade_button_width, 0.0)
		buy_button.add_theme_font_size_override("font_size", _theme_config.small_font_size)
		buy_button.add_theme_stylebox_override("normal", _style_box(_theme_config.button_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
		buy_button.add_theme_stylebox_override("hover", _style_box(_theme_config.button_hover_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
		buy_button.add_theme_stylebox_override("disabled", _style_box(_theme_config.button_disabled_background, Color.TRANSPARENT, 0, _theme_config.panel_corner_radius))
		buy_button.pressed.connect(Callable(self, "_on_buy_upgrade_pressed").bind(planet_id, upgrade.id))
		content.add_child(buy_button)

	margin.add_child(content)
	row.add_child(margin)
	return row

func _upgrade_cost_text(upgrade: PlanetUpgradeDefinition, is_unlocked: bool) -> String:
	if is_unlocked:
		return "FREIGESCHALTET"
	var result := "%d %s" % [upgrade.cost_amount, String(upgrade.cost_resource).capitalize()]
	if upgrade.cost_workers > 0:
		result += "  ·  %d Arbeiter" % upgrade.cost_workers
	return result

func _upgrade_trait_text(upgrade: PlanetUpgradeDefinition) -> String:
	if upgrade.trait_definition == null:
		return ""
	var traits: Array[String] = []
	var trait_data: TraitDefinition = upgrade.trait_definition
	if trait_data.production_boost > 0.0:
		traits.append("Produktion +%d%%" % int(trait_data.production_boost * 100.0))
	if trait_data.worker_spawn_bonus > 0:
		traits.append("Nachschub +%d" % trait_data.worker_spawn_bonus)
	if trait_data.cluster_tier_bonus > 0:
		traits.append("Flotten-Tier +%d" % trait_data.cluster_tier_bonus)
	if trait_data.defense_rating > 0:
		traits.append("Verteidigung +%d" % trait_data.defense_rating)
	if trait_data.perimeter_slots_bonus > 0:
		traits.append("Perimeter-Slots +%d" % trait_data.perimeter_slots_bonus)
	if trait_data.range_bonus > 0.0:
		traits.append("Reichweite +%.0f" % trait_data.range_bonus)
	if trait_data.transfer_speed_multiplier > 1.0:
		traits.append("Transit x%.1f" % trait_data.transfer_speed_multiplier)
	if not String(trait_data.maintenance_cost_resource).is_empty() and trait_data.maintenance_cost_amount > 0:
		traits.append("Unterhalt %d %s" % [trait_data.maintenance_cost_amount, String(trait_data.maintenance_cost_resource).capitalize()])
	return " · ".join(traits)

func _on_buy_upgrade_pressed(planet_id: StringName, upgrade_id: StringName) -> void:
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null or not is_instance_valid(_current_active_planet):
		return
	var upgrade: PlanetUpgradeDefinition = _upgrade_catalog.resolve(upgrade_id)
	if upgrade == null:
		return
	var available_workers: int = int(_current_active_planet.get("worker_count"))
	if not state.purchase_upgrade(planet_id, upgrade_id, _upgrade_catalog, available_workers):
		return
	if upgrade.cost_workers > 0:
		_current_active_planet.call("unregister_workers", upgrade.cost_workers)
	_refresh_upgrade_list(_current_active_planet)
	layout_requested.emit()

func set_selected_count(count: int) -> void:
	_ensure_node_references()
	_selected_count_label.text = "Einheiten: %d" % count

func _ensure_selection_overview_controls() -> void:
	if _content == null:
		return
	if _selection_count_label == null:
		_selection_count_label = Label.new()
		_selection_count_label.name = "SelectionCountLabel"
		var heading_size: int = _theme_config.heading_font_size if _theme_config != null else 16
		_selection_count_label.add_theme_font_size_override("font_size", heading_size)
		_selection_count_label.add_theme_color_override("font_color", DEFAULT_TRANSFORMER_CONFIG.selection_ring_color if DEFAULT_TRANSFORMER_CONFIG != null else Color(0.6, 0.85, 1.0))
		_selection_count_label.visible = false
		_content.add_child(_selection_count_label)
		_content.move_child(_selection_count_label, 0)
	if _selection_overview_box == null:
		_selection_overview_box = VBoxContainer.new()
		_selection_overview_box.name = "SelectionOverview"
		_selection_overview_box.visible = false
		_content.add_child(_selection_overview_box)
		_content.move_child(_selection_overview_box, 1)
	if _selection_total_label == null:
		_selection_total_label = Label.new()
		_selection_total_label.name = "SelectionTotalLabel"
		_selection_total_label.add_theme_font_size_override("font_size", _theme_config.selected_count_font_size if _theme_config != null else 12)
		_selection_overview_box.add_child(_selection_total_label)
	if _selection_clear_button == null:
		_selection_clear_button = Button.new()
		_selection_clear_button.name = "SelectionClearButton"
		_selection_clear_button.text = "AUSWAHL AUFHEBEN"
		_selection_clear_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size if _theme_config != null else 14)
		if not _selection_clear_button.pressed.is_connected(_on_selection_clear_pressed):
			_selection_clear_button.pressed.connect(_on_selection_clear_pressed)
		_selection_overview_box.add_child(_selection_clear_button)

func _on_selection_clear_pressed() -> void:
	clear_selection_pressed.emit()

func set_selection_overview(selection: Array) -> void:
	_ensure_node_references()
	_ensure_selection_overview_controls()
	if _selection_overview_box == null:
		return
	var show_overview: bool = selection.size() > 1
	_selection_count_label.visible = show_overview
	_selection_overview_box.visible = show_overview
	if not show_overview:
		return
	_selection_count_label.text = "%d Planeten ausgewählt" % selection.size()
	_rebuild_selection_overview(selection)

func _rebuild_selection_overview(selection: Array) -> void:
	# Remove generated rows before queue_free so repeated modifier clicks do not
	# leave deferred children in the container or corrupt insertion indices.
	for child in _selection_overview_box.get_children():
		if child == _selection_total_label or child == _selection_clear_button:
			continue
		_selection_overview_box.remove_child(child)
		child.queue_free()
	# Spawn a row per selected planet with name + faction + worker count.
	var total_workers: int = 0
	var player_hits: int = 0
	var cpu_hits: int = 0
	var neutral_hits: int = 0
	var state: Node = get_tree().root.get_node_or_null("GameState")
	for planet in selection:
		if planet == null or not is_instance_valid(planet):
			continue
		var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
		var faction_id: StringName = state.faction_of(planet_id) if state != null else GameState.FACTION_NEUTRAL
		var worker_value: Variant = planet.get("worker_count")
		var workers: int = int(worker_value) if worker_value is int or worker_value is float else 0
		total_workers += workers
		match String(faction_id):
			String(GameState.FACTION_PLAYER): player_hits += 1
			String(GameState.FACTION_CPU): cpu_hits += 1
			_: neutral_hits += 1
		var row_label: Label = Label.new()
		var faction_short: String = "[A]" if faction_id == GameState.FACTION_PLAYER else ("[B]" if faction_id == GameState.FACTION_CPU else "[·]")
		row_label.text = " %s %s · %d Einheiten" % [faction_short, String(planet.name), workers]
		row_label.add_theme_color_override("font_color", DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction_id))
		_selection_overview_box.add_child(row_label)
		if _selection_total_label != null:
			_selection_overview_box.move_child(row_label, _selection_total_label.get_index())
	if _selection_total_label != null:
		var composition: String = "[A] %d · [B] %d · [·] %d" % [player_hits, cpu_hits, neutral_hits]
		_selection_total_label.text = "Gesamt: %d Einheiten · %s" % [total_workers, composition]
	layout_requested.emit()


func update_count(planet: Node2D) -> void:
	if not _count_labels.has(planet):
		return
	var count_label: Label = _count_labels[planet]
	count_label.text = _count_text(planet)

func set_amount_bounds(bounds: Vector2i) -> void:
	_ensure_node_references()
	_amount_slider.min_value = bounds.x
	_amount_slider.max_value = bounds.y
	_amount_slider.editable = bounds.y > 0
	if _amount_slider.value > bounds.y:
		_amount_slider.value = bounds.y
	_send_button.disabled = bounds.y <= 0

func reset_amount() -> void:
	_ensure_node_references()
	_amount_slider.set_value_no_signal(1)

func selected_amount() -> int:
	_ensure_node_references()
	return int(_amount_slider.value)

func selected_mission_type() -> StringName:
	_ensure_node_references()
	if _mission_option == null or _mission_option.selected < 0:
		return &"military"
	var meta: Variant = _mission_option.get_item_metadata(_mission_option.selected)
	return meta as StringName if meta != null else &"military"

func set_mission_type(mission_type: StringName) -> void:
	_ensure_node_references()
	if _mission_option == null:
		return
	for index in _mission_option.item_count:
		if _mission_option.get_item_metadata(index) == mission_type:
			_mission_option.select(index)
			_on_mission_selected(index)
			break

func has_selectable_amount() -> bool:
	_ensure_node_references()
	return _amount_slider.editable

func set_preview(text: String) -> void:
	_ensure_node_references()
	_preview_label.text = text

func index_of_destination(destination_name: String) -> int:
	_ensure_node_references()
	for index in _destination_option.item_count:
		var meta: Variant = _destination_option.get_item_metadata(index)
		if (meta != null and str(meta) == destination_name) or _destination_option.get_item_text(index) == destination_name:
			return index
	return -1

func get_destination_option() -> OptionButton:
	_ensure_node_references()
	return _destination_option

func get_amount_slider() -> HSlider:
	_ensure_node_references()
	return _amount_slider

func get_preview_label() -> Label:
	_ensure_node_references()
	return _preview_label

func get_send_button() -> Button:
	_ensure_node_references()
	return _send_button

func get_count_label(planet: Node2D) -> Label:
	return _count_labels.get(planet) as Label

func _count_text(planet: Node2D) -> String:
	return "%s: %d" % [planet.name, int(planet.get("worker_count"))]

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_mission_selected(index: int) -> void:
	var meta: Variant = _mission_option.get_item_metadata(index)
	mission_selected.emit(meta as StringName if meta != null else &"military")

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and _send_button != null and not _send_button.disabled and event.is_action_pressed(&"ui_accept"):
		_on_send_pressed()
		get_viewport().set_input_as_handled()
