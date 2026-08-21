@tool
class_name UIThemeConfig
extends Resource

@export_range(0.1, 0.6, 0.01) var panel_width_ratio: float
@export_range(120.0, 1000.0, 1.0) var panel_min_width: float
@export_range(120.0, 1000.0, 1.0) var panel_max_width: float
@export_range(0.0, 100.0, 1.0) var edge_margin: float
@export_range(0.0, 100.0, 1.0) var tab_height: float
@export_range(0.0, 100.0, 1.0) var panel_gap: float
@export_range(0.0, 100.0, 1.0) var content_margin_left: int
@export_range(0.0, 100.0, 1.0) var content_margin_top: int
@export_range(0.0, 100.0, 1.0) var content_margin_right: int
@export_range(0.0, 100.0, 1.0) var content_margin_bottom: int
@export_range(0.0, 100.0, 1.0) var content_separation: int
@export_range(0.0, 100.0, 1.0) var list_separation: int
@export_range(1, 96, 1) var tab_font_size: int
@export_range(1, 96, 1) var heading_font_size: int
@export_range(1, 96, 1) var selected_count_font_size: int
@export var panel_background: Color
@export var panel_border: Color
@export_group("Background Assets")
@export var main_menu_background_texture: Texture2D
@export var tech_menu_background_texture: Texture2D
@export var ship_hangar_background_texture: Texture2D
@export var planet_panel_background_texture: Texture2D
@export var pause_menu_background_texture: Texture2D
@export var modal_background_texture: Texture2D
@export var tab_text_color: Color
@export var heading_text_color: Color
@export var selected_planet_text_color: Color
@export var selected_count_text_color: Color
@export var secondary_text_color: Color
@export var accent_text_color: Color
@export var route_line_color: Color
@export_range(0.0, 1.0, 0.01) var route_line_alpha: float
@export_range(0.0, 1.0, 0.01) var route_line_pulse_alpha: float
@export_range(0.0, 20.0, 0.01) var route_line_pulse_speed: float
@export_range(0.1, 20.0, 0.1) var route_line_width: float
@export_range(0, 32, 1) var panel_border_width: int
@export_range(0, 64, 1) var panel_corner_radius: int
@export_range(240.0, 1000.0, 1.0) var resource_bar_max_width: float = 560.0
@export_range(24.0, 80.0, 1.0) var resource_bar_height: float = 34.0
@export_range(80.0, 240.0, 1.0) var tab_width: float = 126.0
@export_range(40.0, 240.0, 1.0) var upgrade_button_width: float = 62.0
@export_range(8, 48, 1) var body_font_size: int = 13
@export_range(8, 48, 1) var small_font_size: int = 11
@export_range(8, 48, 1) var section_font_size: int = 12
@export_range(8, 64, 1) var panel_title_font_size: int = 20
@export_range(0, 24, 1) var card_padding: int = 10
@export_range(20.0, 64.0, 1.0) var section_row_height: float = 30.0
@export_range(0.05, 1.0, 0.05) var transition_duration: float = 0.18
@export_group("Message Feed")
@export_range(0.5, 30.0, 0.5) var message_toast_duration: float = 4.0
@export_range(0.1, 2.0, 0.1) var message_toast_fade_duration: float = 0.5
@export_range(1, 20, 1) var message_max_visible_toasts: int = 6
@export_range(10, 10000, 1) var message_max_log_entries: int = 200
@export_range(20.0, 128.0, 1.0) var technology_icon_size: float = 42.0
@export var card_background: Color = Color(0.045, 0.07, 0.13, 0.96)
@export var input_background: Color = Color(0.025, 0.04, 0.08, 0.98)
@export var input_hover_background: Color = Color(0.08, 0.13, 0.2, 0.98)
@export var button_background: Color = Color(0.08, 0.28, 0.34, 0.98)
@export var button_hover_background: Color = Color(0.12, 0.42, 0.48, 0.98)
@export var button_disabled_background: Color = Color(0.08, 0.1, 0.14, 0.92)
@export var muted_text_color: Color = Color(0.52, 0.63, 0.72, 1.0)
@export var branch_economy_color: Color = Color(0.3, 0.85, 0.5, 1.0)
@export var branch_military_color: Color = Color(1.0, 0.38, 0.34, 1.0)
@export var branch_tech_color: Color = Color(0.42, 0.65, 1.0, 1.0)
@export var branch_infrastructure_color: Color = Color(1.0, 0.72, 0.28, 1.0)

# Ressourcen-Signatur-Farben (nie hardcoded im Code — immer via Config)
@export var resource_color_energy: Color = Color(0.3, 0.9, 1.0)
@export var resource_color_biomass: Color = Color(0.3, 0.9, 0.4)
@export var resource_color_rare: Color = Color(0.7, 0.4, 1.0)
@export var resource_color_material: Color = Color(0.7, 0.75, 0.8)
@export var resource_color_volatile: Color = Color(1.0, 0.6, 0.2)

func resource_color(resource_id: StringName) -> Color:
	match resource_id:
		GameState.RES_ENERGY:   return resource_color_energy
		GameState.RES_BIOMASS:  return resource_color_biomass
		GameState.RES_RARE:     return resource_color_rare
		GameState.RES_MATERIAL: return resource_color_material
		GameState.RES_VOLATILE: return resource_color_volatile
		_:           return accent_text_color

func branch_color(branch: StringName) -> Color:
	match branch:
		&"economy": return branch_economy_color
		&"military": return branch_military_color
		&"tech": return branch_tech_color
		&"infrastructure": return branch_infrastructure_color
		_: return accent_text_color

func make_style_box(background: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = float(card_padding)
	style.content_margin_top = float(card_padding)
	style.content_margin_right = float(card_padding)
	style.content_margin_bottom = float(card_padding)
	return style

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if panel_width_ratio <= 0.0:
		errors.append("UI panel_width_ratio must be positive")
	if panel_min_width <= 0.0 or panel_max_width < panel_min_width:
		errors.append("UI panel width range is invalid")
	if edge_margin < 0.0 or tab_height < 0.0 or panel_gap < 0.0:
		errors.append("UI spacing values cannot be negative")
	if content_margin_left < 0 or content_margin_top < 0 or content_margin_right < 0 or content_margin_bottom < 0:
		errors.append("UI content margins cannot be negative")
	if content_separation < 0 or list_separation < 0:
		errors.append("UI separations cannot be negative")
	if panel_border_width < 0 or panel_corner_radius < 0:
		errors.append("UI panel style values cannot be negative")
	if resource_bar_max_width <= 0.0 or resource_bar_height <= 0.0 or tab_width <= 0.0 or upgrade_button_width <= 0.0:
		errors.append("UI HUD dimensions must be positive")
	if tab_font_size < 1 or heading_font_size < 1 or selected_count_font_size < 1 or body_font_size < 1 or small_font_size < 1 or section_font_size < 1 or panel_title_font_size < 1:
		errors.append("UI font sizes must be positive")
	if card_padding < 0 or section_row_height <= 0.0:
		errors.append("UI card spacing values are invalid")
	if transition_duration <= 0.0:
		errors.append("UI transition_duration must be positive")
	if message_toast_duration <= 0.0 or message_toast_fade_duration <= 0.0 or message_max_visible_toasts < 1:
		errors.append("UI message feed tuning is invalid")
	if message_max_log_entries < 1:
		errors.append("UI message_max_log_entries must be positive")
	if technology_icon_size <= 0.0:
		errors.append("UI technology_icon_size must be positive")
	if route_line_alpha < 0.0 or route_line_alpha > 1.0 or route_line_pulse_alpha < 0.0 or route_line_alpha + route_line_pulse_alpha > 1.0:
		errors.append("UI route line alpha values are invalid")
	if route_line_pulse_speed < 0.0 or route_line_width <= 0.0:
		errors.append("UI route line tuning is invalid")
	return errors
