class_name VaultBar
extends PanelContainer

signal economy_requested()

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const ICON_ENERGY: Texture2D = preload("res://assets/ui/resources/resource_energy.svg")
const ICON_BIOMASS: Texture2D = preload("res://assets/ui/resources/resource_biomass.svg")
const ICON_RARE: Texture2D = preload("res://assets/ui/resources/resource_rare.svg")
const ICON_MATERIAL: Texture2D = preload("res://assets/ui/resources/resource_material.svg")
const ICON_VOLATILE: Texture2D = preload("res://assets/ui/resources/resource_volatile.svg")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _income_rates: Dictionary = {}
## QS-4: Credit-Einkommen-Rate (pro Sekunde), von refresh(state) gesetzt.
var _credit_rate: float = 0.0
var _economy_manager: Node
var _tick_remaining: float = -1.0
var _tick_interval: float = 10.0

@onready var _label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/VaultLabel")
@onready var _credit_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/CreditLabel")
@onready var _transport_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/TransportStatusLabel")
@onready var _rate_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/IncomeRateLabel")

func _icon_for(resource_id: StringName) -> Texture2D:
	match resource_id:
		GameState.RES_ENERGY:   return ICON_ENERGY
		GameState.RES_BIOMASS:  return ICON_BIOMASS
		GameState.RES_RARE:     return ICON_RARE
		GameState.RES_MATERIAL: return ICON_MATERIAL
		GameState.RES_VOLATILE: return ICON_VOLATILE
		_: return null

func setup(theme_config: UIThemeConfig = null, economy_manager: Node = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_economy_manager = economy_manager
	_refresh_tick_status()
	_apply_theme()

func refresh(state: Node) -> void:
	if _label == null or state == null:
		return
	var player_faction: StringName = GameState.FACTION_PLAYER
	var parts: Array[String] = []
	for resource_id in GameState.ALL_RESOURCES:
		parts.append(_resource_segment(resource_id, state.get_faction_resource(player_faction, resource_id)))
	_label.text = " | ".join(parts)
	if _credit_label != null:
		_credit_label.text = "[color=#f2c14e]Credits: %d[/color]" % state.get_faction_credits(player_faction)
	_refresh_transport_label(state)
	_refresh_tick_status()
	# QS-4: Credit-Rate aus EconomyConfig ableiten.
	_credit_rate = 0.0
	if _tick_interval > 0.0 and state.has_method("economy_domain"):
		var econ = state.economy_domain()
		if econ != null and econ.has_method("credit_income_per_colony"):
			_credit_rate = float(econ.credit_income_per_colony()) / _tick_interval
	_refresh_income_rate_label()
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2(1.02, 1.02), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)

func _refresh_transport_label(state: Node) -> void:
	if _transport_label == null or state == null or not state.has_method("get_worker_transport_records"):
		return
	var records: Array[Dictionary] = state.get_worker_transport_records(GameState.FACTION_PLAYER)
	if records.is_empty():
		_transport_label.text = "Transport: keine aktiven Routen"
		return
	var outbound := 0
	var loading := 0
	var returning := 0
	for record in records:
		match record.get("phase", &"outbound"):
			&"outbound": outbound += 1
			&"loading": loading += 1
			&"returning": returning += 1
	_transport_label.text = "Transport: %d raus · %d laden · %d zurück" % [outbound, loading, returning]

func _process(_delta: float) -> void:
	if _rate_label == null or _economy_manager == null:
		return
	_refresh_tick_status()
	_refresh_income_rate_label()

func _refresh_tick_status() -> void:
	if _economy_manager == null:
		return
	if _economy_manager.has_method("economy_tick_remaining"):
		_tick_remaining = float(_economy_manager.economy_tick_remaining())
	if _economy_manager.has_method("economy_tick_interval"):
		_tick_interval = maxf(float(_economy_manager.economy_tick_interval()), 0.1)

func record_income(resource_id: StringName, amount: int, interval_seconds: float) -> void:
	if amount <= 0 or String(resource_id).is_empty():
		return
	var interval: float = maxf(interval_seconds, 0.1)
	_income_rates[resource_id] = float(amount) / interval
	_refresh_income_rate_label()

func clear_income_rates() -> void:
	_income_rates.clear()
	_refresh_income_rate_label()

func _resource_segment(resource_id: StringName, amount: int) -> String:
	var icon := _icon_for(resource_id)
	var icon_tag := ""
	if icon != null:
		icon_tag = "[img=18x18]%s[/img] " % icon.resource_path
	return "%s[color=%s]%d[/color]" % [icon_tag, _theme_config.resource_color(resource_id).to_html(false), amount]

func _refresh_income_rate_label() -> void:
	if _rate_label == null:
		return
	var segments: Array[String] = []
	for resource_id in GameState.ALL_RESOURCES:
		var rate: float = float(_income_rates.get(resource_id, 0.0))
		if rate <= 0.0:
			continue
		var icon := _icon_for(resource_id)
		var icon_tag := ""
		if icon != null:
			icon_tag = "[img=14x14]%s[/img] " % icon.resource_path
		var rate_text: String = "%.0f" % rate if is_equal_approx(rate, round(rate)) else "%.1f" % rate
		segments.append("[color=%s]%s+%s/s[/color]" % [_theme_config.resource_color(resource_id).to_html(false), icon_tag, rate_text])
	var income_text: String = " | ".join(segments) if not segments.is_empty() else "noch kein Ertrag"
	var tick_text: String = ""
	if _tick_remaining >= 0.0:
		tick_text = " · Nächster Tick: %.1fs" % _tick_remaining
	elif _tick_interval > 0.0:
		tick_text = " · Automatik noch nicht aktiv"
	# QS-4: Credit-Einkommen-Rate anzeigen (pro Sekunde).
	if _credit_rate > 0.0:
		var cr_text: String = "%.1f" % _credit_rate
		if is_equal_approx(_credit_rate, round(_credit_rate)):
			cr_text = "%.0f" % _credit_rate
		segments.append("[color=#f2c14e]+%s Credits/s[/color]" % cr_text)
		income_text = " | ".join(segments)
	_rate_label.text = "Einkommen: " + income_text + tick_text

func _resource_rate_name(resource_id: StringName) -> String:
	match resource_id:
		GameState.RES_ENERGY:
			return "Energie"
		GameState.RES_BIOMASS:
			return "Biomasse"
		GameState.RES_RARE:
			return "Exotisch"
		GameState.RES_MATERIAL:
			return "Material"
		GameState.RES_VOLATILE:
			return "Volatil"
		_:
			return String(resource_id)

func _apply_theme() -> void:
	add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.panel_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius)
	)
	if _label != null:
		_label.add_theme_font_size_override("normal_font_size", _theme_config.small_font_size)
	if _credit_label != null:
		_credit_label.add_theme_font_size_override("normal_font_size", _theme_config.small_font_size)
	if _transport_label != null:
		_transport_label.add_theme_font_size_override("normal_font_size", _theme_config.small_font_size)
	if _rate_label != null:
		_rate_label.add_theme_font_size_override("normal_font_size", _theme_config.small_font_size)
	# Make the bar clickable so it opens the full economy window.
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		economy_requested.emit()
		accept_event()