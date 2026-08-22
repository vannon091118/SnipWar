class_name EconomyWindow
extends Control

## Modal overlay showing full economic breakdown:
## vault totals, income rates, transport routes, and tick status per resource.
## Opened by clicking the VaultBar; closes via X button or ESC.

signal closed()

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_ECONOMY: EconomyConfig = preload("res://resources/config/economy_default.tres")
const ICON_ENERGY: Texture2D = preload("res://assets/ui/resources/resource_energy.svg")
const ICON_BIOMASS: Texture2D = preload("res://assets/ui/resources/resource_biomass.svg")
const ICON_RARE: Texture2D = preload("res://assets/ui/resources/resource_rare.svg")
const ICON_MATERIAL: Texture2D = preload("res://assets/ui/resources/resource_material.svg")
const ICON_VOLATILE: Texture2D = preload("res://assets/ui/resources/resource_volatile.svg")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _economy_manager: Node
var _state: Node

func setup(theme_config: UIThemeConfig = null, economy_manager: Node = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_economy_manager = economy_manager
	# _state is resolved after add_child, inside _build_content.

func _ready() -> void:
	_state = get_tree().root.get_node_or_null("GameState")
	_build_content()

func _build_content() -> void:
	# Semi-transparent backdrop captures clicks behind the panel.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	add_child(backdrop)
	backdrop.gui_input.connect(_on_backdrop_input)

	# Panel centred on screen.
	var panel := PanelContainer.new()
	panel.name = "EconomyPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box: StyleBoxFlat = _theme_config.make_style_box(
		Color(0.06, 0.07, 0.10, 0.97),
		_theme_config.panel_border, 1, _theme_config.panel_corner_radius
	)
	panel.add_theme_stylebox_override("panel", box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title row with close button.
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "WIRTSCHAFT & EINKOMMEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", _theme_config.panel_title_font_size)
	title.add_theme_color_override("font_color", _theme_config.accent_text_color)
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)
	vbox.add_child(title_row)

	# Credits row.
	var credits := Label.new()
	credits.text = _credits_text()
	credits.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
	credits.add_theme_color_override("font_color", Color(0.95, 0.76, 0.31))
	vbox.add_child(credits)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Per-resource summary blocks.
	for res_id in GameState.ALL_RESOURCES:
		var block := _resource_block(res_id)
		vbox.add_child(block)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Transport summary.
	var transport := Label.new()
	transport.text = _transport_text()
	transport.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	transport.add_theme_color_override("font_color", _theme_config.muted_text_color)
	vbox.add_child(transport)

	# Tick status.
	var tick := Label.new()
	tick.text = _tick_text()
	tick.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	tick.add_theme_color_override("font_color", _theme_config.muted_text_color)
	vbox.add_child(tick)

	add_child(panel)

	# Centre panel on screen.
	await get_tree().process_frame
	var vsize: Vector2 = get_viewport().get_visible_rect().size
	panel.position = (vsize - panel.size) * 0.5

func _resource_block(resource_id: StringName) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var icon_tex: Texture2D = _icon_for(resource_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(24, 24)
		header.add_child(icon)

	var name_label := Label.new()
	name_label.text = UIBaseUtils.resource_display_name(resource_id)
	name_label.add_theme_font_size_override("font_size", _theme_config.section_font_size)
	name_label.add_theme_color_override("font_color", _theme_config.resource_color(resource_id))
	header.add_child(name_label)
	block.add_child(header)

	if _state != null:
		var amount: int = int(_state.get_faction_resource(GameState.FACTION_PLAYER, resource_id))
		var amount_label := Label.new()
		amount_label.text = "  Vorrat: %d" % amount
		amount_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
		block.add_child(amount_label)

		# Owned planets producing this resource.
		var income := _income_sources_text(resource_id)
		if not income.is_empty():
			var income_label := Label.new()
			income_label.text = "  + %s" % income
			income_label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
			income_label.add_theme_color_override("font_color", _theme_config.resource_color(resource_id).lightened(0.25))
			block.add_child(income_label)

	return block

func _income_sources_text(resource_id: StringName) -> String:
	if _state == null:
		return ""
	var parts: Array[String] = []
	var field: Node = get_parent().get_parent() if get_parent() != null else null
	if field == null:
		return ""
	var snapshot: Array = field.get_children().duplicate()
	for child in snapshot:
		if not is_instance_valid(child):
			continue
		var planet: Planet = child as Planet
		if planet == null:
			continue
		if _state.faction_of(planet.planet_id) != GameState.FACTION_PLAYER:
			continue
		# Check if this planet generates this resource type.
		var planet_resource: StringName = _state.resource_of(planet.planet_id) if _state.has_method("resource_of") else &""
		if planet_resource == resource_id:
			# Use economy_config.tick_interval for rate calculation.
			var interval: float = DEFAULT_ECONOMY.tick_interval if DEFAULT_ECONOMY != null else 10.0
			var base_amount: int = planet.get_size_profile().resource_base
			parts.append("%s (+%d/%.0fs)" % [UIBaseUtils.planet_display_name(planet), base_amount, interval])
		# Gather workers on this planet also yield resources.
		if _state.has_method("get_gathering_workers"):
			var gatherers: int = int(_state.get_gathering_workers(planet.planet_id))
			if gatherers > 0:
				var rate: int = gatherers * planet.get_size_profile().resource_base
				parts.append("%s (%d Sammler → ~+%d/10s)" % [UIBaseUtils.planet_display_name(planet), gatherers, rate])
	if parts.is_empty():
		return "Keine laufende Produktion"
	return " ·  ".join(parts)

func _credits_text() -> String:
	if _state == null:
		return "Credits: —"
	return "Credits: %d" % _state.get_faction_credits(GameState.FACTION_PLAYER)

func _transport_text() -> String:
	if _state == null or not _state.has_method("get_worker_transport_records"):
		return "Transport: Keine aktiven Routen"
	var records: Array[Dictionary] = _state.get_worker_transport_records(GameState.FACTION_PLAYER)
	if records.is_empty():
		return "Transport: Keine aktiven Routen"
	return "Transport: %d aktive Routen" % records.size()

func _tick_text() -> String:
	if _economy_manager == null:
		return ""
	var remaining: float = -1.0
	var interval: float = 10.0
	if _economy_manager.has_method("economy_tick_remaining"):
		remaining = float(_economy_manager.economy_tick_remaining())
	if _economy_manager.has_method("economy_tick_interval"):
		interval = maxf(float(_economy_manager.economy_tick_interval()), 0.1)
	if remaining >= 0.0:
		return "Nächster Wirtschafts-Tick: %.1f s (Intervall: %.0f s)" % [remaining, interval]
	return "Automatik noch nicht aktiv"

func _icon_for(resource_id: StringName) -> Texture2D:
	match resource_id:
		GameState.RES_ENERGY:   return ICON_ENERGY
		GameState.RES_BIOMASS:  return ICON_BIOMASS
		GameState.RES_RARE:     return ICON_RARE
		GameState.RES_MATERIAL: return ICON_MATERIAL
		GameState.RES_VOLATILE: return ICON_VOLATILE
		_: return null

func _close() -> void:
	closed.emit()
	# Free our parent CanvasLayer too so the layer doesn't linger.
	var parent_layer: Node = get_parent()
	if parent_layer is CanvasLayer:
		parent_layer.queue_free()
	else:
		queue_free()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()