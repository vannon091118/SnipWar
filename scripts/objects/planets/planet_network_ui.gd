class_name PlanetNetworkUI
extends CanvasLayer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")

signal panel_visibility_changed(visible: bool)
signal destination_selected(index: int)
signal mission_selected(mission_type: StringName)
signal amount_changed(value: float)
signal send_pressed

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _upgrade_catalog: PlanetUpgradeCatalog = DEFAULT_UPGRADE_CATALOG
var _count_labels: Dictionary = {}
var _current_active_planet: Node2D

@onready var _ui_root: Control = get_node_or_null("PlanetTabUI")
@onready var _vault_bar: PanelContainer = get_node_or_null("PlanetTabUI/VaultBar")
@onready var _vault_label: RichTextLabel = get_node_or_null("PlanetTabUI/VaultBar/VaultMargin/VaultLabel")
@onready var _tab_button: Button = get_node_or_null("PlanetTabUI/PlanetTab")
@onready var _panel: PanelContainer = get_node_or_null("PlanetTabUI/PlanetPanel")
@onready var _heading_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/HeadingLabel")
@onready var _selected_planet_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedPlanetLabel")
@onready var _faction_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/FactionLabel")
@onready var _resource_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ResourceLabel")
@onready var _selected_count_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedCountLabel")
@onready var _destination_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationHeading")
@onready var _destination_option: OptionButton = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationSelect")
@onready var _mission_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/MissionHeading")
@onready var _mission_option: OptionButton = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/MissionSelect")
@onready var _send_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendHeading")
@onready var _amount_slider: HSlider = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/AmountSlider")
@onready var _preview_label: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/PreviewLabel")
@onready var _send_button: Button = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendButton")
@onready var _upgrade_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UpgradeHeading")
@onready var _upgrade_list: VBoxContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UpgradeScroll/UpgradeList")
@onready var _units_heading: Label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UnitsHeading")
@onready var _count_list: VBoxContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ScrollContainer/CountList")
@onready var _margin: MarginContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer")
@onready var _content: VBoxContainer = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content")

func setup(planets: Array[Node2D], theme_config: UIThemeConfig = null) -> void:
	layer = 50
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ensure_node_references()
	_apply_theme()
	_setup_missions()
	_connect_internal_signals()
	_populate_units_list(planets)
	_connect_game_state_signals()
	_update_vault_display()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()

func _ensure_node_references() -> void:
	if _ui_root == null:
		_ui_root = get_node_or_null("PlanetTabUI")
	if _vault_bar == null:
		_vault_bar = get_node_or_null("PlanetTabUI/VaultBar")
	if _vault_label == null:
		_vault_label = get_node_or_null("PlanetTabUI/VaultBar/VaultMargin/VaultLabel")
	if _tab_button == null:
		_tab_button = get_node_or_null("PlanetTabUI/PlanetTab")
	if _panel == null:
		_panel = get_node_or_null("PlanetTabUI/PlanetPanel")
	if _heading_label == null:
		_heading_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/HeadingLabel")
	if _selected_planet_label == null:
		_selected_planet_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedPlanetLabel")
	if _faction_label == null:
		_faction_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/FactionLabel")
	if _resource_label == null:
		_resource_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ResourceLabel")
	if _selected_count_label == null:
		_selected_count_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SelectedCountLabel")
	if _destination_heading == null:
		_destination_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationHeading")
	if _destination_option == null:
		_destination_option = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/DestinationSelect")
	if _mission_heading == null:
		_mission_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/MissionHeading")
	if _mission_option == null:
		_mission_option = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/MissionSelect")
	if _send_heading == null:
		_send_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendHeading")
	if _amount_slider == null:
		_amount_slider = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/AmountSlider")
	if _preview_label == null:
		_preview_label = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/PreviewLabel")
	if _send_button == null:
		_send_button = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/SendButton")
	if _upgrade_heading == null:
		_upgrade_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UpgradeHeading")
	if _upgrade_list == null:
		_upgrade_list = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UpgradeScroll/UpgradeList")
	if _units_heading == null:
		_units_heading = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/UnitsHeading")
	if _count_list == null:
		_count_list = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content/ScrollContainer/CountList")
	if _margin == null:
		_margin = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer")
	if _content == null:
		_content = get_node_or_null("PlanetTabUI/PlanetPanel/MarginContainer/Content")

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
	_mission_option.select(0)

func _connect_game_state_signals() -> void:
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null:
		return
	if not state.faction_resources_changed.is_connected(_on_faction_resources_changed):
		state.faction_resources_changed.connect(_on_faction_resources_changed)
	if not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)

func _on_faction_resources_changed(faction: StringName, _resource_id: StringName, _new_amount: int) -> void:
	# The vault bar and affordability only concern the player faction; ignore CPU ticks
	# and skip rebuilding the (hidden) upgrade list while the panel is closed.
	if faction != GameState.FACTION_PLAYER:
		return
	_update_vault_display()
	if _current_active_planet != null and _panel != null and _panel.visible:
		_refresh_upgrade_list(_current_active_planet)

func _on_planet_upgraded(planet_id: StringName, _upgrade_id: StringName) -> void:
	_update_vault_display()
	if _current_active_planet != null and _panel != null and _panel.visible and _current_active_planet.get("planet_id") == planet_id:
		_refresh_upgrade_list(_current_active_planet)

func _update_vault_display() -> void:
	_ensure_node_references()
	if _vault_label == null:
		return
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null:
		return
	var player_faction: StringName = GameState.FACTION_PLAYER
	var energy: int = state.get_faction_resource(player_faction, &"energy")
	var biomass: int = state.get_faction_resource(player_faction, &"biomass")
	var rare: int = state.get_faction_resource(player_faction, &"rare")
	var material: int = state.get_faction_resource(player_faction, &"material")
	var volatile_mat: int = state.get_faction_resource(player_faction, &"volatile")
	_vault_label.text = "%s | %s | %s | %s | %s" % [
		_resource_segment("Energie", energy, &"energy"),
		_resource_segment("Biomasse", biomass, &"biomass"),
		_resource_segment("Exotisch", rare, &"rare"),
		_resource_segment("Material", material, &"material"),
		_resource_segment("Volatil", volatile_mat, &"volatile")
	]

func _resource_segment(label: String, amount: int, resource_id: StringName) -> String:
	return "[color=%s]%s: %d[/color]" % [_theme_config.resource_color(resource_id).to_html(false), label, amount]

func _apply_theme() -> void:
	if _tab_button != null:
		_tab_button.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
		_tab_button.add_theme_color_override("font_color", _theme_config.tab_text_color)

	if _panel != null:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = _theme_config.panel_background
		panel_style.border_color = _theme_config.panel_border
		panel_style.border_width_left = _theme_config.panel_border_width
		panel_style.border_width_top = _theme_config.panel_border_width
		panel_style.border_width_right = _theme_config.panel_border_width
		panel_style.border_width_bottom = _theme_config.panel_border_width
		panel_style.corner_radius_top_left = _theme_config.panel_corner_radius
		panel_style.corner_radius_top_right = _theme_config.panel_corner_radius
		panel_style.corner_radius_bottom_left = _theme_config.panel_corner_radius
		panel_style.corner_radius_bottom_right = _theme_config.panel_corner_radius
		_panel.add_theme_stylebox_override("panel", panel_style)

	if _margin != null:
		_margin.add_theme_constant_override("margin_left", _theme_config.content_margin_left)
		_margin.add_theme_constant_override("margin_top", _theme_config.content_margin_top)
		_margin.add_theme_constant_override("margin_right", _theme_config.content_margin_right)
		_margin.add_theme_constant_override("margin_bottom", _theme_config.content_margin_bottom)

	if _content != null:
		_content.add_theme_constant_override("separation", _theme_config.content_separation)

	if _heading_label != null:
		_heading_label.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
		_heading_label.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _selected_planet_label != null:
		_selected_planet_label.add_theme_color_override("font_color", _theme_config.selected_planet_text_color)

	if _selected_count_label != null:
		_selected_count_label.add_theme_font_size_override("font_size", _theme_config.selected_count_font_size)
		_selected_count_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)

	if _destination_heading != null:
		_destination_heading.add_theme_color_override("font_color", _theme_config.secondary_text_color)

	if _send_heading != null:
		_send_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _preview_label != null:
		_preview_label.add_theme_color_override("font_color", _theme_config.selected_count_text_color)

	if _units_heading != null:
		_units_heading.add_theme_color_override("font_color", _theme_config.heading_text_color)

	if _count_list != null:
		_count_list.add_theme_constant_override("separation", _theme_config.list_separation)

func _connect_internal_signals() -> void:
	if _tab_button != null and not _tab_button.pressed.is_connected(_toggle_panel):
		_tab_button.pressed.connect(_toggle_panel)
	if _destination_option != null and not _destination_option.item_selected.is_connected(_on_destination_selected):
		_destination_option.item_selected.connect(_on_destination_selected)
	if _mission_option != null and not _mission_option.item_selected.is_connected(_on_mission_selected):
		_mission_option.item_selected.connect(_on_mission_selected)
	if _amount_slider != null and not _amount_slider.value_changed.is_connected(_on_amount_changed):
		_amount_slider.value_changed.connect(_on_amount_changed)
	if _send_button != null and not _send_button.pressed.is_connected(_on_send_pressed):
		_send_button.pressed.connect(_on_send_pressed)

func _populate_units_list(planets: Array[Node2D]) -> void:
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

func show_planet(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	_ensure_node_references()
	_current_active_planet = planet
	_panel.visible = true
	_tab_button.set_pressed_no_signal(true)
	_apply_responsive_layout()
	_selected_planet_label.text = "Planet: %s" % planet.name

	var state: Node = get_tree().root.get_node_or_null("GameState")
	var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
	if state != null:
		var faction_id: StringName = state.faction_of(planet_id)
		var faction_str: String = "Spieler [A]" if faction_id == &"a" else ("CPU [B]" if faction_id == &"b" else "Neutral")
		if _faction_label != null:
			_faction_label.text = "Besitzer: %s" % faction_str
			_faction_label.add_theme_color_override("font_color", DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction_id))

		var resource_id: StringName = state.resource_of(planet_id)
		var resource_name: String = String(resource_id).capitalize() if not String(resource_id).is_empty() else "Keine"
		if _resource_label != null:
			_resource_label.text = "Ressource: %s" % resource_name
			_resource_label.add_theme_color_override("font_color", _theme_config.resource_color(resource_id))

	_destination_option.clear()
	_destination_option.disabled = destinations.is_empty()
	for destination in destinations:
		_destination_option.add_item(destination.name)
	if default_destination != null:
		for index in _destination_option.item_count:
			if _destination_option.get_item_text(index) == default_destination.name:
				_destination_option.select(index)
				break

	_refresh_upgrade_list(planet)

func _refresh_upgrade_list(planet: Node2D) -> void:
	if _upgrade_list == null:
		return
	for child in _upgrade_list.get_children():
		child.queue_free()

	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null or _upgrade_catalog == null:
		return

	var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
	var unlocked_upgrades: Array[StringName] = state.get_planet_upgrades(planet_id)
	var is_player_owned: bool = state.owns(planet_id, &"a")

	# Group upgrades by branch
	var branch_order := [&"economy", &"military", &"tech", &"infrastructure"]
	var branch_colors := {
		&"economy": Color(0.3, 0.8, 0.4),
		&"military": Color(0.9, 0.3, 0.3),
		&"tech": Color(0.4, 0.6, 0.9),
		&"infrastructure": Color(0.8, 0.6, 0.2)
	}
	var branch_titles := {
		&"economy": "WIRTSCHAFT",
		&"military": "MILITÄR",
		&"tech": "TECHNOLOGIE",
		&"infrastructure": "INFRASTRUKTUR"
	}

	for branch in branch_order:
		var branch_upgrades: Array[PlanetUpgradeDefinition] = _upgrade_catalog.get_upgrades_for_branch(branch)
		if branch_upgrades.is_empty():
			continue

		# Branch header
		var branch_header := HBoxContainer.new()
		branch_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var branch_label := Label.new()
		branch_label.text = "▸ %s" % branch_titles.get(branch, branch.capitalize())
		branch_label.add_theme_font_size_override("font_size", 14)
		branch_label.add_theme_color_override("font_color", branch_colors.get(branch, Color.WHITE))
		branch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		branch_header.add_child(branch_label)
		_upgrade_list.add_child(branch_header)

		# Separator line
		var sep := HSeparator.new()
		sep.add_theme_color_override("separation_color", branch_colors.get(branch, Color.WHITE))
		_upgrade_list.add_child(sep)

		# Upgrades in this branch
		for upgrade in branch_upgrades:
			if upgrade == null:
				continue
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var is_unlocked := unlocked_upgrades.has(upgrade.id)
			var can_buy: bool = is_player_owned and state.can_purchase_upgrade(planet_id, upgrade.id, _upgrade_catalog, int(planet.get("worker_count")))

			var info_label := Label.new()
			info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var trait_text := ""
			if upgrade.trait_definition != null:
				var traits: Array[String] = []
				if upgrade.trait_definition.production_boost > 0.0:
					traits.append("Prod: +%d%%" % int(upgrade.trait_definition.production_boost * 100))
				if upgrade.trait_definition.worker_spawn_bonus > 0:
					traits.append("Spawn: +%d" % upgrade.trait_definition.worker_spawn_bonus)
				if upgrade.trait_definition.cluster_tier_bonus > 0:
					traits.append("Tier: +%d" % upgrade.trait_definition.cluster_tier_bonus)
				if upgrade.trait_definition.defense_rating > 0:
					traits.append("Def: +%d" % upgrade.trait_definition.defense_rating)
				if upgrade.trait_definition.perimeter_slots_bonus > 0:
					traits.append("Slots: +%d" % upgrade.trait_definition.perimeter_slots_bonus)
				if upgrade.trait_definition.range_bonus > 0.0:
					traits.append("Reichw: +%d" % int(upgrade.trait_definition.range_bonus))
				if upgrade.trait_definition.transfer_speed_multiplier > 1.0:
					traits.append("Speed: x%.1f" % upgrade.trait_definition.transfer_speed_multiplier)
				if not String(upgrade.trait_definition.maintenance_cost_resource).is_empty() and upgrade.trait_definition.maintenance_cost_amount > 0:
					traits.append("Unterhalt: %d %s" % [upgrade.trait_definition.maintenance_cost_amount, upgrade.trait_definition.maintenance_cost_resource])
				if not traits.is_empty():
					trait_text = " [%s]" % ", ".join(traits)

			var cost_text: String = "Gekauft" if is_unlocked else "%d %s" % [upgrade.cost_amount, upgrade.cost_resource]
			if not is_unlocked and upgrade.cost_workers > 0:
				cost_text += " + %d Arbeiter" % upgrade.cost_workers
			info_label.text = "%s: %s%s" % [upgrade.display_name, cost_text, trait_text]
			info_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if is_unlocked else Color(0.8, 0.8, 0.8))
			info_label.tooltip_text = upgrade.description
			row.add_child(info_label)

			if not is_unlocked:
				var buy_btn := Button.new()
				buy_btn.text = "Bauen"
				buy_btn.disabled = not can_buy
				buy_btn.pressed.connect(Callable(self, "_on_buy_upgrade_pressed").bind(planet_id, upgrade.id))
				row.add_child(buy_btn)

			_upgrade_list.add_child(row)

func _on_buy_upgrade_pressed(planet_id: StringName, upgrade_id: StringName) -> void:
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null or _current_active_planet == null:
		return
	var upgrade: PlanetUpgradeDefinition = _upgrade_catalog.resolve(upgrade_id)
	if upgrade == null:
		return
	var available_workers: int = int(_current_active_planet.get("worker_count"))
	if not state.purchase_upgrade(planet_id, upgrade_id, _upgrade_catalog, available_workers):
		return
	if upgrade.cost_workers > 0:
		_current_active_planet.call("unregister_workers", upgrade.cost_workers)

func set_selected_count(count: int) -> void:
	_ensure_node_references()
	_selected_count_label.text = "Einheiten: %d" % count

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

func has_selectable_amount() -> bool:
	_ensure_node_references()
	return _amount_slider.editable

func set_preview(text: String) -> void:
	_ensure_node_references()
	_preview_label.text = text

func is_panel_visible() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	_toggle_panel()

func get_panel() -> PanelContainer:
	_ensure_node_references()
	return _panel

func index_of_destination(destination_name: String) -> int:
	_ensure_node_references()
	for index in _destination_option.item_count:
		if _destination_option.get_item_text(index) == destination_name:
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

func _apply_responsive_layout() -> void:
	if not is_instance_valid(_tab_button) or not is_instance_valid(_panel):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var panel_width := clampf(
		viewport_size.x * _theme_config.panel_width_ratio,
		_theme_config.panel_min_width,
		_theme_config.panel_max_width
	)
	_tab_button.offset_left = -panel_width
	_tab_button.offset_top = _theme_config.edge_margin
	_tab_button.offset_right = -_theme_config.edge_margin
	_tab_button.offset_bottom = _theme_config.edge_margin + _theme_config.tab_height
	_panel.offset_left = -panel_width
	_panel.offset_top = _theme_config.edge_margin + _theme_config.tab_height + _theme_config.panel_gap
	_panel.offset_right = -_theme_config.edge_margin
	_panel.offset_bottom = -_theme_config.edge_margin

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()

func _toggle_panel() -> void:
	_ensure_node_references()
	_panel.visible = not _panel.visible
	_tab_button.set_pressed_no_signal(_panel.visible)
	panel_visibility_changed.emit(_panel.visible)

func _on_destination_selected(index: int) -> void:
	destination_selected.emit(index)

func _on_mission_selected(index: int) -> void:
	var meta: Variant = _mission_option.get_item_metadata(index)
	mission_selected.emit(meta as StringName if meta != null else &"military")

func _on_amount_changed(value: float) -> void:
	amount_changed.emit(value)

func _on_send_pressed() -> void:
	send_pressed.emit()
