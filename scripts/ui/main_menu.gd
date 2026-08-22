class_name MainMenu
extends Control

## Entry scene of the game flow. "Neues Spiel" starts a fresh run,
## "Weiter" restores a saved run (slot 0) and returns to the world.
## Scene switches are delegated to the SceneDirectorService autoload so the
## fade transition and GameState context handover stay centralized.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const SAVE_SLOT: int = 0

var _title: Label
var _new_game_button: Button
var _continue_button: Button
var _quit_button: Button
var _hint: Label

func _ready() -> void:
	_build_ui()
	_refresh_continue()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Backdrop"
	overlay.color = Color(0.02, 0.02, 0.05, 0.98)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_title = Label.new()
	_title.text = "SNIPWAR"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 46)
	_title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	content.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = "EISEN-GRENZE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	content.add_child(subtitle)

	content.add_child(_spacer(22.0))

	_new_game_button = _menu_button("NEUES SPIEL")
	_new_game_button.name = "NewGameButton"
	_new_game_button.pressed.connect(_on_new_game_pressed)
	content.add_child(_new_game_button)

	_continue_button = _menu_button("WEITER")
	_continue_button.name = "ContinueButton"
	_continue_button.pressed.connect(_on_continue_pressed)
	content.add_child(_continue_button)

	_quit_button = _menu_button("BEENDEN")
	_quit_button.name = "QuitButton"
	_quit_button.pressed.connect(_on_quit_pressed)
	content.add_child(_quit_button)

	content.add_child(_spacer(22.0))

	_hint = Label.new()
	_hint.text = "Strategische Overworld · Flottengefechte · Planetare Eroberung"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	content.add_child(_hint)

func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	return button

func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer

func _refresh_continue() -> void:
	if _continue_button == null:
		return
	var service: Node = get_node_or_null("/root/SaveGameService")
	_continue_button.disabled = service == null or not service.has_save(SAVE_SLOT)

func _on_new_game_pressed() -> void:
	var service: Node = get_node_or_null("/root/SaveGameService")
	if service != null and service.has_method("delete_save"):
		service.delete_save(SAVE_SLOT)
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and state.has_method("request_new_run"):
		state.request_new_run()
	_goto_world()

func _on_continue_pressed() -> void:
	var service: Node = get_node_or_null("/root/SaveGameService")
	if service == null or not service.load_run(SAVE_SLOT):
		_refresh_continue()
		return
	_goto_world()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _goto_world() -> void:
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"world")
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
