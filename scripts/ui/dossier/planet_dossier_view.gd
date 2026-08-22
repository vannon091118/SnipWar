class_name PlanetDossierView
extends Control

## Fullscreen planet dossier: left side renders a paper planet disc with
## rotating orbital rings, right side shows build slots as magnet tiles that
## reuse the live upgrade catalog and purchase path.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _upgrade_catalog: PlanetUpgradeCatalog = DEFAULT_UPGRADE_CATALOG
var _planet: Planet
var _state: Node
var _phase := 0.0
var _slot_content: VBoxContainer
var _left_info: VBoxContainer

func setup(theme_config: UIThemeConfig = null, upgrade_catalog: PlanetUpgradeCatalog = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_upgrade_catalog = upgrade_catalog if upgrade_catalog != null else DEFAULT_UPGRADE_CATALOG
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func populate(planet: Planet, state: Node) -> void:
	_planet = planet
	_state = state
	_refresh_left_info()
	_rebuild_slots()
	queue_redraw()

func _build_ui() -> void:
	_left_info = VBoxContainer.new()
	_left_info.name = "LeftInfo"
	_left_info.anchor_left = 0.0
	_left_info.anchor_top = 0.52
	_left_info.anchor_right = 0.42
	_left_info.anchor_bottom = 1.0
	_left_info.offset_left = 16.0
	_left_info.offset_top = 0.0
	_left_info.offset_right = -16.0
	_left_info.offset_bottom = -16.0
	_left_info.add_theme_constant_override("separation", _theme_config.list_separation)
	_left_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_info)

	var scroll := ScrollContainer.new()
	scroll.name = "BuildSlotsScroll"
	scroll.anchor_left = 0.46
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

func _refresh_left_info() -> void:
	for child in _left_info.get_children():
		_left_info.remove_child(child)
		child.queue_free()
	if _planet == null or not is_instance_valid(_planet) or _state == null:
		return
	var name_text: String = UIBaseUtils.planet_display_name(_planet)
	_left_info.add_child(UIBaseUtils.make_label(name_text.to_upper(), _theme_config.heading_text_color, _theme_config.panel_title_font_size))
	var faction_id: StringName = _state.faction_of(_planet.planet_id)
	var faction_str: String = UIBaseUtils.faction_display_name(faction_id)
	var faction_label := UIBaseUtils.make_label("Status: %s" % faction_str, DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction_id), _theme_config.body_font_size)
	_left_info.add_child(faction_label)
	var resource_id: StringName = _state.resource_of(_planet.planet_id) if _state.is_known(_planet.planet_id, GameState.FACTION_PLAYER) else &""
	var resource_text: String = UIBaseUtils.resource_display_name(resource_id) if not String(resource_id).is_empty() else "Unbekannt (Forschungsschiff benötigt)"
	_left_info.add_child(UIBaseUtils.make_label("Produktion: %s" % resource_text, _theme_config.resource_color(resource_id), _theme_config.body_font_size))
	_left_info.add_child(UIBaseUtils.make_label(
		"Bauplätze: %d  ·  Perimeter: %d  ·  Reichweite: %.0f px" % [_planet.get_build_slot_count(), _planet.get_perimeter_slots(), _planet.get_defense_range()],
		_theme_config.secondary_text_color,
		_theme_config.small_font_size
	))

func _rebuild_slots() -> void:
	for child in _slot_content.get_children():
		_slot_content.remove_child(child)
		child.queue_free()
	if _planet == null or not is_instance_valid(_planet) or _state == null or _upgrade_catalog == null:
		return
	var planet_id: StringName = _planet.planet_id
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

func _magnet_tile(planet_id: StringName, upgrade: PlanetUpgradeDefinition, is_unlocked: bool, is_owned: bool) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(170.0, 0.0)
	tile.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.card_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius)
	)
	tile.tooltip_text = upgrade.description
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", _theme_config.list_separation)
	content.add_child(UIBaseUtils.make_label(upgrade.display_name, _theme_config.accent_text_color, _theme_config.body_font_size, false))
	content.add_child(UIBaseUtils.make_label(_cost_text(upgrade, is_unlocked), _theme_config.muted_text_color, _theme_config.small_font_size, false))
	if not is_unlocked:
		var buy := Button.new()
		buy.text = "BAUEN"
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = not is_owned or not _state.can_purchase_upgrade(planet_id, upgrade.id, _upgrade_catalog, int(_planet.get("worker_count")))
		buy.pressed.connect(_buy_upgrade.bind(planet_id, upgrade.id))
		content.add_child(buy)
	tile.add_child(content)
	return tile

func _cost_text(upgrade: PlanetUpgradeDefinition, is_unlocked: bool) -> String:
	if is_unlocked:
		return "FREIGESCHALTET"
	var result: String = UIBaseUtils.cost_text(upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost)
	if upgrade.workers_required > 0:
		result += " · Arbeitskräfte: %d" % upgrade.workers_required
	return result

func _buy_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	if _state == null or _planet == null or not is_instance_valid(_planet):
		return
	var upgrade: PlanetUpgradeDefinition = _upgrade_catalog.resolve(upgrade_id)
	if upgrade == null:
		return
	var available_workers: int = int(_planet.get("worker_count"))
	if not _state.purchase_upgrade(planet_id, upgrade_id, _upgrade_catalog, available_workers):
		return
	# Workers are temporarily reserved by construction jobs, never consumed.
	_rebuild_slots()

func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var left_width := size.x * 0.44
	var center := Vector2(left_width * 0.5, size.y * 0.34)
	var radius := minf(left_width * 0.40, size.y * 0.30)
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
