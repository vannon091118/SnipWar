class_name VaultBar
extends PanelContainer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME

@onready var _label: RichTextLabel = get_node_or_null("VaultMargin/VaultLabel")

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
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2(1.02, 1.02), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)

func _resource_segment(label: String, amount: int, resource_id: StringName) -> String:
	return "[color=%s]%s: %d[/color]" % [_theme_config.resource_color(resource_id).to_html(false), label, amount]

func _apply_theme() -> void:
	add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.panel_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius)
	)
	if _label != null:
		_label.add_theme_font_size_override("normal_font_size", _theme_config.small_font_size)
