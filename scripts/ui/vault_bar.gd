class_name VaultBar
extends PanelContainer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _income_rates: Dictionary = {}

@onready var _label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/VaultLabel")
@onready var _credit_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/CreditLabel")
@onready var _transport_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/TransportStatusLabel")
@onready var _rate_label: RichTextLabel = get_node_or_null("VaultMargin/VaultContent/IncomeRateLabel")

func setup(theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_apply_theme()

func refresh(state: Node) -> void:
	if _label == null or state == null:
		return
	var player_faction: StringName = GameState.FACTION_PLAYER
	_label.text = "%s | %s | %s | %s | %s" % [
		_resource_segment("Energie", state.get_faction_resource(player_faction, GameState.RES_ENERGY), GameState.RES_ENERGY),
		_resource_segment("Biomasse", state.get_faction_resource(player_faction, GameState.RES_BIOMASS), GameState.RES_BIOMASS),
		_resource_segment("Exotisch", state.get_faction_resource(player_faction, GameState.RES_RARE), GameState.RES_RARE),
		_resource_segment("Material", state.get_faction_resource(player_faction, GameState.RES_MATERIAL), GameState.RES_MATERIAL),
		_resource_segment("Volatil", state.get_faction_resource(player_faction, GameState.RES_VOLATILE), GameState.RES_VOLATILE)
	]
	if _credit_label != null:
		_credit_label.text = "[color=#f2c14e]Credits: %d[/color]" % state.get_faction_credits(player_faction)
	_refresh_transport_label(state)
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

func record_income(resource_id: StringName, amount: int, interval_seconds: float) -> void:
	if amount <= 0 or String(resource_id).is_empty():
		return
	var interval: float = maxf(interval_seconds, 0.1)
	_income_rates[resource_id] = float(amount) / interval
	_refresh_income_rate_label()

func clear_income_rates() -> void:
	_income_rates.clear()
	_refresh_income_rate_label()

func _resource_segment(label: String, amount: int, resource_id: StringName) -> String:
	return "[color=%s]%s: %d[/color]" % [_theme_config.resource_color(resource_id).to_html(false), label, amount]

func _refresh_income_rate_label() -> void:
	if _rate_label == null:
		return
	var segments: Array[String] = []
	for resource_id in GameState.ALL_RESOURCES:
		var rate: float = float(_income_rates.get(resource_id, 0.0))
		if rate <= 0.0:
			continue
		var rate_text: String = "%.0f" % rate if is_equal_approx(rate, round(rate)) else "%.1f" % rate
		segments.append("[color=%s]+%s/s %s[/color]" % [_theme_config.resource_color(resource_id).to_html(false), rate_text, _resource_rate_name(resource_id)])
	_rate_label.text = "Einkommen: " + (" | ".join(segments) if not segments.is_empty() else "wartet auf Tick")

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
