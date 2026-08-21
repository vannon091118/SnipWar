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
