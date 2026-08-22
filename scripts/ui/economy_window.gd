class_name EconomyWindow
extends Control

## Persistent economy module showing per-resource vault totals, income sources,
## transport routes, and tick status. Lives on its own CanvasLayer and toggles
## open/closed via the "ECONOMY" dossier button or VaultBar click.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_ECONOMY: EconomyConfig = preload("res://resources/config/economy_default.tres")
const ICON_ENERGY: Texture2D = preload("res://assets/ui/resources/resource_energy.svg")
const ICON_BIOMASS: Texture2D = preload("res://assets/ui/resources/resource_biomass.svg")
const ICON_RARE: Texture2D = preload("res://assets/ui/resources/resource_rare.svg")
const ICON_MATERIAL: Texture2D = preload("res://assets/ui/resources/resource_material.svg")
const ICON_VOLATILE: Texture2D = preload("res://assets/ui/resources/resource_volatile.svg")

signal closed()

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _economy_manager: Node
var _state: Node
var _visible: bool = false

# Content nodes rebuilt each toggle-open so data is always fresh.
var _backdrop: ColorRect
var _panel: PanelContainer
var _content_vbox: VBoxContainer
var _content_built: bool = false

func setup(theme_config: UIThemeConfig = null, economy_manager: Node = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_economy_manager = economy_manager
	# Build backdrop and panel shell once; content is rebuilt on each open.
	_grow_shell()
	hide()

func is_open() -> bool:
	return _visible

func toggle() -> void:
	if _visible:
		close()
	else:
		open()

func open() -> void:
	if _visible:
		return
	_state = get_tree().root.get_node_or_null("GameState")
	_economy_manager = _find_economy_manager()
	_build_content()
	_bind_signals()
	show()
	_visible = true

func close() -> void:
	if not _visible:
		return
	_unbind_signals()
	_clear_content()
	hide()
	_visible = false
	closed.emit()

# ── shell (once) ─────────────────────────────────────────────────────

func _grow_shell() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	_panel = PanelContainer.new()
	_panel.name = "EconomyPanel"
	_panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = SIZE_SHRINK_CENTER
	var box: StyleBoxFlat = _theme_config.make_style_box(
		Color(0.06, 0.07, 0.10, 0.97),
		_theme_config.panel_border, 1, _theme_config.panel_corner_radius
	)
	_panel.add_theme_stylebox_override("panel", box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(_content_vbox)

	add_child(_panel)

func _find_economy_manager() -> Node:
	# Walk up: CanvasLayer → PlanetNetwork → SeededLayout → EconomyManager
	var ancestor: Node = self
	while ancestor != null:
		if ancestor is CanvasLayer:
			ancestor = ancestor.get_parent()
			continue
		var em: Node = ancestor.get_node_or_null("EconomyManager") if ancestor != null else null
		if em != null:
			return em
		ancestor = ancestor.get_parent() if ancestor != null else null
	return null

# ── content (per open) ───────────────────────────────────────────────

func _build_content() -> void:
	_clear_content()

	# Title row with close button.
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "WIRTSCHAFT & EINKOMMEN"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", _theme_config.panel_title_font_size)
	title.add_theme_color_override("font_color", _theme_config.accent_text_color)
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)
	_content_vbox.add_child(title_row)

	# Credits.
	_content_vbox.add_child(_make_credit_label())

	var sep1 := HSeparator.new()
	_content_vbox.add_child(sep1)

	# Per-resource blocks.
	for res_id in GameState.ALL_RESOURCES:
		_content_vbox.add_child(_resource_block(res_id))

	var sep2 := HSeparator.new()
	_content_vbox.add_child(sep2)

	# Transport.
	_content_vbox.add_child(_make_transport_label())

	# Tick.
	_content_vbox.add_child(_make_tick_label())

	# Centre.
	await get_tree().process_frame
	var vsize: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = (vsize - _panel.size) * 0.5
	_content_built = true

func _clear_content() -> void:
	_content_built = false
	for child in _content_vbox.get_children():
		child.queue_free()

func refresh() -> void:
	"""Re-read GameState and rebuild the content tree."""
	if not _visible or not _content_built:
		return
	_state = get_tree().root.get_node_or_null("GameState")
	_economy_manager = _find_economy_manager()
	_build_content()

# ── signal binding ───────────────────────────────────────────────────

func _bind_signals() -> void:
	if _state != null:
		if _state.has_signal("faction_resources_changed") and not _state.faction_resources_changed.is_connected(_on_faction_resources_changed):
			_state.faction_resources_changed.connect(_on_faction_resources_changed)
		if _state.has_signal("credits_changed") and not _state.credits_changed.is_connected(_on_credits_changed):
			_state.credits_changed.connect(_on_credits_changed)
		if _state.has_signal("worker_transport_phase_changed") and not _state.worker_transport_phase_changed.is_connected(_on_transport_changed):
			_state.worker_transport_phase_changed.connect(_on_transport_changed)

func _unbind_signals() -> void:
	if _state != null:
		if _state.has_signal("faction_resources_changed") and _state.faction_resources_changed.is_connected(_on_faction_resources_changed):
			_state.faction_resources_changed.disconnect(_on_faction_resources_changed)
		if _state.has_signal("credits_changed") and _state.credits_changed.is_connected(_on_credits_changed):
			_state.credits_changed.disconnect(_on_credits_changed)
		if _state.has_signal("worker_transport_phase_changed") and _state.worker_transport_phase_changed.is_connected(_on_transport_changed):
			_state.worker_transport_phase_changed.disconnect(_on_transport_changed)

func _on_faction_resources_changed(faction: StringName, _resource_id: StringName, _new_amount: int) -> void:
	if faction == GameState.FACTION_PLAYER:
		refresh()

func _on_credits_changed(faction: StringName, _amount: int) -> void:
	if faction == GameState.FACTION_PLAYER:
		refresh()

func _on_transport_changed(_transport_id: StringName, _phase: StringName) -> void:
	refresh()

# ── building blocks ──────────────────────────────────────────────────

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
	var field: Node = _find_seeded_layout()
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
		var planet_resource: StringName = _state.resource_of(planet.planet_id) if _state.has_method("resource_of") else &""
		if planet_resource == resource_id:
			var interval: float = DEFAULT_ECONOMY.tick_interval if DEFAULT_ECONOMY != null else 10.0
			var base_amount: int = planet.get_size_profile().resource_base
			parts.append("%s (+%d/%.0fs)" % [UIBaseUtils.planet_display_name(planet), base_amount, interval])
		if _state.has_method("get_gathering_workers"):
			var gatherers: int = int(_state.get_gathering_workers(GameState.FACTION_PLAYER, planet.planet_id))
			if gatherers > 0:
				var rate: int = gatherers * planet.get_size_profile().resource_base
				parts.append("%s (%d Sammler → ~+%d/10s)" % [UIBaseUtils.planet_display_name(planet), gatherers, rate])
	if parts.is_empty():
		return "Keine laufende Produktion"
	return " ·  ".join(parts)

func _find_seeded_layout() -> Node:
	# EconomyWindow → CanvasLayer → PlanetNetwork → SeededLayout
	var layer: Node = get_parent()
	if layer == null:
		return null
	var network: Node = layer.get_parent()
	if network == null:
		return null
	return network.get_parent()

func _make_credit_label() -> Label:
	var label := Label.new()
	label.text = _credits_text()
	label.add_theme_font_size_override("font_size", _theme_config.heading_font_size)
	label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.31))
	return label

func _make_transport_label() -> Label:
	var label := Label.new()
	label.text = _transport_text()
	label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	return label

func _make_tick_label() -> Label:
	var label := Label.new()
	label.text = _tick_text()
	label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	return label

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

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()