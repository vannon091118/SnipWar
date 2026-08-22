class_name UIBaseUtils

## Centralized UI styling and node generation helpers to avoid duplicated boilerplate across UI views.

static func style_box(
	theme: UIThemeConfig,
	background: Color,
	border: Color = Color.TRANSPARENT,
	border_width: int = 0,
	radius: int = 0
) -> StyleBoxFlat:
	if theme != null:
		return theme.make_style_box(background, border, border_width, radius)
	var box := StyleBoxFlat.new()
	box.bg_color = background
	if border != Color.TRANSPARENT and border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	if radius > 0:
		box.set_corner_radius_all(radius)
	return box

static func texture_style_box(
	theme: UIThemeConfig,
	texture: Texture2D,
	fallback_background: Color,
	content_margin: float = 0.0
) -> StyleBox:
	if texture == null:
		return style_box(theme, fallback_background)
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = content_margin
	box.texture_margin_top = content_margin
	box.texture_margin_right = content_margin
	box.texture_margin_bottom = content_margin
	box.content_margin_left = content_margin
	box.content_margin_top = content_margin
	box.content_margin_right = content_margin
	box.content_margin_bottom = content_margin
	return box

static func make_label(text: String, color: Color, font_size: int, autowrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if autowrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label

static func make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return separator

static func apply_button_theme(button: Button, theme: UIThemeConfig) -> void:
	if button == null or theme == null:
		return
	button.add_theme_font_size_override("font_size", theme.tab_font_size)
	button.add_theme_color_override("font_color", theme.tab_text_color)
	button.add_theme_stylebox_override(
		"normal",
		style_box(theme, theme.button_background, theme.panel_border, theme.panel_border_width, theme.panel_corner_radius)
	)
	button.add_theme_stylebox_override(
		"hover",
		style_box(theme, theme.button_hover_background, theme.panel_border, theme.panel_border_width, theme.panel_corner_radius)
	)
	button.add_theme_stylebox_override(
		"pressed",
		style_box(theme, theme.button_hover_background, theme.panel_border, theme.panel_border_width, theme.panel_corner_radius)
	)

static func resource_display_name(resource_id: StringName) -> String:
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
			return String(resource_id).capitalize()

static func faction_display_name(faction: StringName) -> String:
	match faction:
		GameState.FACTION_PLAYER:
			return "Eigene Welt"
		GameState.FACTION_CPU:
			return "Gegnerische Welt"
		GameState.FACTION_NEUTRAL:
			return "Neutrale Welt"
		_:
			return "Unbekannt"

static func planet_display_name(planet: Node) -> String:
	if planet == null:
		return "Unbekannter Planet"
	var display_name: Variant = planet.get("display_name")
	if display_name != null and not String(display_name).is_empty():
		return String(display_name)
	return "Unbekannter Planet"

static func mission_display_name(mission_type: StringName) -> String:
	match mission_type:
		GameState.MISSION_MILITARY:
			return "Militär"
		GameState.MISSION_CARGO:
			return "Transport"
		GameState.MISSION_COLONY:
			return "Kolonie"
		GameState.MISSION_COLLECT:
			return "Sammeln"
		_:
			return String(mission_type).capitalize()

static func mission_description(mission_type: StringName) -> String:
	match mission_type:
		GameState.MISSION_MILITARY:
			return "Angriff oder Verstärkung — ein Konflikt ist möglich."
		GameState.MISSION_CARGO:
			return "Transportiert Einheiten zu einer eigenen Welt."
		GameState.MISSION_COLONY:
			return "Besiedelt eine gescannte neutrale Welt."
		GameState.MISSION_COLLECT:
			return "Bindet Einheiten und bringt lokale Ressourcen zurück."
		_:
			return ""

static func research_role(technology: TechnologyDefinition) -> String:
	if technology == null:
		return "SYSTEM"
	if not String(technology.strategic_role).is_empty():
		return String(technology.strategic_role).to_upper()
	if technology.category == TechnologyDefinition.CATEGORY_MECH:
		return "KAMPF"
	if technology.category == TechnologyDefinition.CATEGORY_PLANET:
		return "WIRTSCHAFT"
	if String(technology.effect_id).contains("scan") or String(technology.effect_id).contains("scout"):
		return "EXPLORATION"
	if String(technology.effect_id).contains("weapon"):
		return "KAMPF"
	return "MOBILITÄT"

static func cost_text(resource_id: StringName, amount: int, credit_amount: int = 0) -> String:
	var result: String = "%d %s" % [amount, resource_display_name(resource_id)]
	if credit_amount > 0:
		result += " · %d Credits" % credit_amount
	return result

static func technology_cost_text(technology: TechnologyDefinition, state: Node = null, faction: StringName = GameState.FACTION_PLAYER) -> String:
	if technology == null:
		return ""
	if state != null and state.has_method("get_faction_resource") and state.has_method("get_faction_credits"):
		return "%d/%d %s · %d/%d Credits" % [
			state.get_faction_resource(faction, technology.cost_resource),
			technology.cost_amount,
			resource_display_name(technology.cost_resource),
			state.get_faction_credits(faction),
			technology.credit_cost,
		]
	return cost_text(technology.cost_resource, technology.cost_amount, technology.credit_cost)

static func research_task_name(task_type: StringName) -> String:
	match task_type:
		&"scan":
			return "Scannen"
		&"explore":
			return "Erkunden"
		_:
			return String(task_type).capitalize()
