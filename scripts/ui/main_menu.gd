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
var _intro: PanelContainer
var _name_input: LineEdit
var _profile_label: Label
var _identity_hint: Label

func _ready() -> void:
	_setup_music()
	_build_ui()
	_refresh_continue()

func _setup_music() -> void:
	var music: AudioStreamPlayer = get_node_or_null("Music")
	if music != null:
		music.finished.connect(music.play)
		music.volume_db = -6.0

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
	subtitle.text = "RAND DER GALAXIE"
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
	_show_identity_intro()

func _show_identity_intro() -> void:
	if _intro != null and is_instance_valid(_intro):
		return
	_intro = PanelContainer.new()
	_intro.name = "StickmanIdentityIntro"
	_intro.set_anchors_preset(Control.PRESET_CENTER)
	_intro.custom_minimum_size = Vector2(420.0, 260.0)
	_intro.position = Vector2(-210.0, -130.0)
	_intro.add_theme_stylebox_override("panel", UIBaseUtils.style_box(DEFAULT_THEME, Color(0.035, 0.07, 0.11, 0.98), Color(0.35, 0.85, 0.45), 2, 10))
	add_child(_intro)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_intro.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(UIBaseUtils.make_label("STICKMAN // IDENTITÄTSPROTOKOLL", DEFAULT_THEME.heading_text_color, 18))
	box.add_child(UIBaseUtils.make_label("Rasse: STICKMAN — aus den Resten einer alten Grenzverwaltung gebaut: Papierfasern, Notfalltinte und ein Protokoll, das niemand mehr lesen kann. Sieht simpel aus. Ist Absicht.", DEFAULT_THEME.secondary_text_color, 12))
	_name_input = LineEdit.new()
	_name_input.name = "PlayerNameInput"
	_name_input.placeholder_text = "Dein Name, Commander"
	_name_input.text = "Stickman"
	box.add_child(_name_input)
	_profile_label = UIBaseUtils.make_label("Profil: noch unentschieden", DEFAULT_THEME.muted_text_color, 12)
	box.add_child(_profile_label)
	var profile_row := HBoxContainer.new()
	for profile in ["GUT", "BÖSE", "MILITÄRISCH", "FORSCHER", "BAUMEISTER"]:
		var profile_button := Button.new()
		profile_button.text = profile
		profile_button.focus_mode = Control.FOCUS_NONE
		UIBaseUtils.apply_button_theme(profile_button, DEFAULT_THEME)
		profile_button.pressed.connect(_select_profile.bind(profile))
		profile_row.add_child(profile_button)
	box.add_child(profile_row)
	_identity_hint = UIBaseUtils.make_label("", Color(0.95, 0.62, 0.35), 11)
	box.add_child(_identity_hint)
	var confirm := Button.new()
	confirm.text = "IDENTITÄT FESTLEGEN"
	UIBaseUtils.apply_button_theme(confirm, DEFAULT_THEME)
	confirm.pressed.connect(_confirm_identity)
	box.add_child(confirm)
	_name_input.grab_focus()

func _select_profile(profile: String) -> void:
	# Selbstironische Kurzfassung je Haltung — der Ton des Dossiers bleibt
	# trocken-verwaltlich, die Aussage eindeutig.
	var descriptions := {
		"GUT": "hilft zuerst und fragt spaeter nach der Rechnung.",
		"BÖSE": "Effizienz ist auch eine Moral. Meistens die einzige übrig.",
		"MILITÄRISCH": "Jede Linie wird Formation, jeder Planet Brückenkopf.",
		"FORSCHER": "Das Universum ist ein Rätsel. Den Schraubenschlüssel haben wir schon.",
		"BAUMEISTER": "Sieht drei Bauplätze und eine sehr optimistische Materialliste.",
	}
	var suffix := str(descriptions.get(profile.to_upper(), "charakterstark. Verdächtig."))
	if _profile_label != null:
		_profile_label.text = "Profil %s: %s" % [profile, suffix]
		_profile_label.set_meta("profile", profile)

func _confirm_identity() -> void:
	if _name_input == null or _name_input.text.strip_edges().is_empty():
		if _identity_hint != null:
			_identity_hint.text = "Name erforderlich — das Protokoll akzeptiert keine anonymen Commander."
		return
	if _identity_hint != null:
		_identity_hint.text = ""
	var profile := str(_profile_label.get_meta("profile", "FORSCHER"))
	var state: Node = get_node_or_null("/root/GameState")
	if state != null:
		if state.has_method("set_player_identity"):
			state.set_player_identity(_name_input.text.strip_edges(), profile)
		else:
			state.set_meta("player_name", _name_input.text.strip_edges())
			state.set_meta("stickman_profile", profile)
	if _intro != null:
		_intro.queue_free()
		_intro = null
	var service: Node = get_node_or_null("/root/SaveGameService")
	if service != null and service.has_method("delete_save"):
		service.delete_save(SAVE_SLOT)
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("request_new_run"):
		game_state.request_new_run()
	_goto_historical_world()

func _on_continue_pressed() -> void:
	var service: Node = get_node_or_null("/root/SaveGameService")
	if service == null or not service.load_run(SAVE_SLOT):
		_refresh_continue()
		return
	_goto_world()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _goto_historical_world() -> void:
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"historical_world")
	else:
		get_tree().change_scene_to_file("res://scenes/historical_world/historical_world.tscn")

func _goto_world() -> void:
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"world")
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
