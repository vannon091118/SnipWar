## SelectionActionTooltip — short-lived popover that explains why a context-menu
## action is disabled. Used by Slice 2's selection-aware PlanetContextMenu so
## the player can see the gate condition (e.g. "target is not yet scanned")
## without digging through the technology menu.
class_name SelectionActionTooltip
extends PanelContainer

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _label: Label
var _hide_tween: Tween = null
var _hide_at_msec: int = 0
const AUTO_HIDE_AFTER_MSEC := 2400

func _ready() -> void:
	_build_visuals()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 100

func _build_visuals() -> void:
	if _label != null and is_instance_valid(_label):
		return
	var theme_cfg: UIThemeConfig = DEFAULT_THEME
	var style := theme_cfg.make_style_box(theme_cfg.button_hover_background, theme_cfg.panel_border, 1, theme_cfg.panel_corner_radius)
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.name = "SelectionTooltipLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", theme_cfg.selected_count_font_size)
	_label.add_theme_color_override("font_color", theme_cfg.route_line_color)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(220, 0)
	add_child(_label)

func show_text(reason_text: String, anchor_position: Vector2) -> void:
	_build_visuals()
	if _label == null:
		return
	_label.text = reason_text
	# Anchor the tooltip below the cursor; nudge to stay inside the viewport.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(960, 540)
	var anchor := anchor_position + Vector2(16.0, 16.0)
	if anchor.x + 240.0 > viewport_size.x:
		anchor.x = maxf(0.0, viewport_size.x - 240.0)
	if anchor.y + 96.0 > viewport_size.y:
		anchor.y = maxf(0.0, viewport_size.y - 96.0)
	position = anchor
	visible = true
	modulate.a = 1.0
	_hide_at_msec = Time.get_ticks_msec() + AUTO_HIDE_AFTER_MSEC
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()
	# Refresh the auto-hide timer every show by reusing `_process`.
	set_process(true)

func _process(_delta: float) -> void:
	if not visible:
		set_process(false)
		return
	if Time.get_ticks_msec() >= _hide_at_msec:
		_auto_hide()

func _auto_hide() -> void:
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_hide_tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
	)
