class_name PauseMenu
extends CanvasLayer

signal pause_toggled(paused: bool)

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _overlay: Control
var _content: VBoxContainer
var _title: Label
var _resume_button: Button
var _save_button: Button
var _menu_button: Button
var _hint: Label
var _planet_network: PlanetNetwork

func _ready() -> void:
	var background: Node = get_parent()
	if background != null:
		_planet_network = background.get_node_or_null("PlanetField/PlanetNetwork") as PlanetNetwork
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 70
	_build_ui()
	set_paused(false)

func _build_ui() -> void:
	var texture_overlay := TextureRect.new()
	texture_overlay.texture = DEFAULT_THEME.pause_menu_background_texture
	texture_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_overlay.name = "Overlay"
	texture_overlay.modulate = Color(1.0, 1.0, 1.0, 0.92)
	_overlay = texture_overlay
	if texture_overlay.texture == null:
		var fallback_overlay := ColorRect.new()
		fallback_overlay.color = Color(0.0, 0.0, 0.0, 0.55)
		fallback_overlay.name = "Overlay"
		_overlay = fallback_overlay
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 12)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.visible = false
	add_child(_content)

	_title = Label.new()
	_title.text = "PAUSE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_content.add_child(_title)

	_resume_button = Button.new()
	_resume_button.text = "WEITER"
	_resume_button.custom_minimum_size = Vector2(220.0, 48.0)
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume_button.focus_mode = Control.FOCUS_ALL
	_resume_button.pressed.connect(resume)
	_content.add_child(_resume_button)

	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.text = "SPEICHERN"
	_save_button.custom_minimum_size = Vector2(220.0, 48.0)
	_save_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_save_button.focus_mode = Control.FOCUS_ALL
	_save_button.pressed.connect(_on_save_pressed)
	_content.add_child(_save_button)

	_menu_button = Button.new()
	_menu_button.name = "MenuButton"
	_menu_button.text = "HAUPTMENÜ"
	_menu_button.custom_minimum_size = Vector2(220.0, 48.0)
	_menu_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_button.focus_mode = Control.FOCUS_ALL
	_menu_button.pressed.connect(_on_menu_pressed)
	_content.add_child(_menu_button)

	_hint = Label.new()
	_hint.text = "ESC / LEERTASTE zum Fortsetzen"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_content.add_child(_hint)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if get_tree().paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if get_tree().paused:
		resume()
		get_viewport().set_input_as_handled()
		return
	if _overlay_ui_open():
		return
	pause()
	get_viewport().set_input_as_handled()

func pause() -> void:
	set_paused(true)

func resume() -> void:
	set_paused(false)

func is_paused() -> bool:
	return get_tree().paused

func set_paused(paused: bool) -> void:
	if _overlay != null:
		_overlay.visible = paused
	if _content != null:
		_content.visible = paused
	get_tree().paused = paused
	pause_toggled.emit(paused)

func _on_save_pressed() -> void:
	var service: Node = get_node_or_null("/root/SaveGameService")
	if service == null or not service.has_method("save_run"):
		return
	var saved: bool = bool(service.call("save_run", 0))
	var event_log: Node = get_node_or_null("/root/EventLog")
	if event_log != null and event_log.has_method("push"):
		event_log.call("push", &"system", "Spielstand gespeichert." if saved else "Speichern fehlgeschlagen.")

## Returns to the main menu. The tree must be unpaused first, otherwise the
## freshly booted menu scene would inherit the paused state and stay frozen.
func _on_menu_pressed() -> void:
	set_paused(false)
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"menu")

func _overlay_ui_open() -> bool:
	if _planet_network == null or not is_instance_valid(_planet_network):
		return false
	var ui: PlanetNetworkUI = _planet_network.get_ui()
	if ui != null and ui.is_panel_visible():
		return true
	var coordinator: ModalCoordinator = _planet_network.get_modal_coordinator() if _planet_network.has_method("get_modal_coordinator") else null
	return coordinator != null and coordinator.is_open()
