class_name InputHintOverlay
extends CanvasLayer

## Sprint 6 (S2): small hotkey hint chips in the bottom-right corner. Shows the
## basic camera/zoom keys by default; on planet selection it switches to the
## dossier hotkeys and fades out after a few seconds so it never stays in the
## way. Reappears whenever the context changes.

const FADE_AFTER_SECONDS := 30.0

var _theme_config: UIThemeConfig
var _chips: VBoxContainer
var _fade_tween: Tween
var _current_context := &""

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

func setup(theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	layer = 85
	_build_ui()
	show_context(&"base")

func _build_ui() -> void:
	_chips = VBoxContainer.new()
	_chips.name = "InputHints"
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.add_theme_constant_override("separation", 4)
	add_child(_chips)
	_reset_position()

func _reset_position() -> void:
	# Bottom-right, above the fleet/economy zones.
	_chips.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chips.position = Vector2(-260.0, -96.0)

func show_context(context: StringName) -> void:
	if _current_context == context:
		return
	_current_context = context
	for child in _chips.get_children():
		child.queue_free()
	var hints: Array[String] = []
	if context == &"planet":
		hints = [
			"[P] Planetendossier",
			"[W] Werkstatt",
			"[F] Forschung",
			"[R] Ressourcen",
			"[ESC] Schließen",
		]
	else:
		hints = [
			"[W A S D] Kamera",
			"[Mausrad] Zoom",
			"[Linksklick] Planet wählen",
			"[Rechtsklick] Kontextmenü",
			"[ESC] Menü",
		]
	for hint in hints:
		var label := Label.new()
		label.text = hint
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 0.95))
		_chips.add_child(label)
	_restart_fade()

func _restart_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_chips.modulate.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_interval(FADE_AFTER_SECONDS)
	_fade_tween.tween_property(_chips, "modulate:a", 0.0, 1.0)