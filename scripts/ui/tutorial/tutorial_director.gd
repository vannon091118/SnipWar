class_name TutorialDirector
extends CanvasLayer

## Interaktives Onboarding: führt den Spieler Schritt für Schritt durch die
## erste Partie (Kamera → Planetenwahl → Forschung → Bau → Werkstatt → Scout).
## Jeder Schritt hat eine Karte mit Ziel-Marker (Weltposition oder UI-Button)
## und eine Abschluss-Bedingung, die über GameState-Signale/Prädikate geprüft
## wird. WEITER überspringt einen Schritt manuell; TUTORIAL-Button im
## DossierLauncher startet neu. Es gibt bewusst KEINE vordefinierten
## Test-Szenarien für den Ablauf — die MCP-Agenten entdecken die Oberfläche
## selbst und erweitern ihre Bibliothek über das Playthrough-Archiv.

const MAX_STEPS := 8
const POLL_INTERVAL := 0.35

var _theme_config: UIThemeConfig
var _planet_network: Node
var _ship_manager: Node
var _map_camera: Node
var _state: Node
var _steps: Array = []
var _step_index := 0
var _poll_accumulator := 0.0
var _active := false
var _auto_started := false

var _dim: ColorRect
var _marker: Control
var _card: PanelContainer
var _title_label: Label
var _text_label: Label
var _counter_label: Label
var _weiter_button: Button
var _marker_target: Vector2
var _marker_target_valid := false

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

func setup(theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	layer = 92
	_build_ui()
	hide_overlay()

func is_active() -> bool:
	return _active

func start(planet_network: Node, ship_manager: Node, state: Node, map_camera: Node) -> void:
	_planet_network = planet_network
	_ship_manager = ship_manager
	_state = state
	_map_camera = map_camera
	_build_steps()
	_step_index = 0
	_auto_started = true
	_active = true
	_show_overlay()
	_present_step()

## Öffentlicher Restart für den TUTORIAL-Launcher-Button.
func restart() -> void:
	start(_planet_network, _ship_manager, _state, _map_camera)

func skip_all() -> void:
	_active = false
	hide_overlay()

# ── UI-Aufbau ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "TutorialDim"
	_dim.color = Color(0.01, 0.015, 0.03, 0.45)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_marker = Control.new()
	_marker.name = "TutorialMarker"
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)

	_card = PanelContainer.new()
	_card.name = "TutorialCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.texture_style_box(_theme_config, _theme_config.modal_background_texture, _theme_config.panel_background, float(_theme_config.card_padding))
	)
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.offset_left = -320.0
	_card.offset_right = 320.0
	_card.offset_top = -150.0
	_card.offset_bottom = -28.0
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title_label = Label.new()
	_title_label.name = "TutorialTitle"
	_title_label.add_theme_font_size_override("font_size", _theme_config.section_font_size)
	_title_label.add_theme_color_override("font_color", _theme_config.accent_text_color)
	column.add_child(_title_label)

	_text_label = Label.new()
	_text_label.name = "TutorialText"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(600.0, 0.0)
	_text_label.add_theme_font_size_override("font_size", _theme_config.body_font_size)
	_text_label.add_theme_color_override("font_color", _theme_config.secondary_text_color)
	column.add_child(_text_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	_counter_label = Label.new()
	_counter_label.name = "TutorialCounter"
	_counter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter_label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	_counter_label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	row.add_child(_counter_label)

	_weiter_button = Button.new()
	_weiter_button.name = "TutorialWeiter"
	_weiter_button.text = "WEITER ›"
	_weiter_button.focus_mode = Control.FOCUS_NONE
	UIBaseUtils.apply_button_theme(_weiter_button, _theme_config)
	_weiter_button.pressed.connect(_on_weiter_pressed)
	row.add_child(_weiter_button)

	var skip_button := Button.new()
	skip_button.name = "TutorialSkip"
	skip_button.text = "ÜBERSPRINGEN"
	skip_button.focus_mode = Control.FOCUS_NONE
	UIBaseUtils.apply_button_theme(skip_button, _theme_config)
	skip_button.pressed.connect(skip_all)
	row.add_child(skip_button)

func _show_overlay() -> void:
	_dim.visible = true
	_marker.visible = true
	_card.visible = true

func hide_overlay() -> void:
	_dim.visible = false
	_marker.visible = false
	_card.visible = false
	_marker_target_valid = false

# ── Schritte ───────────────────────────────────────────────────────────

func _build_steps() -> void:
	_steps = []
	_steps.append({
		"id": "camera",
		"title": "WILLKOMMEN BEI SNIPWAR",
		"text": "Bewege die Kamera mit [W A S D] und zoome mit dem Mausrad. Deine Heimatwelt trägt den grünen Ring.",
		"predicate": null,
		"target": "planet",
	})
	_steps.append({
		"id": "select_homeworld",
		"title": "PLANET WÄHLEN",
		"text": "Klicke deine Heimatwelt an. Rechts öffnet sich das Planeten-Panel für Missionen und Versand.",
		"predicate": Callable(self, "_homeworld_selected"),
		"target": "planet",
	})
	_steps.append({
		"id": "research",
		"title": "ERSTE FORSCHUNG",
		"text": "Öffne links [F] FORSCHUNG und starte im Forschungsbaum „Orbitales Werft-Design“ (grüner Rahmen = lernbar).",
		"predicate": Callable(self, "_research_started"),
		"target": "button:FORSCHUNG",
	})
	_steps.append({
		"id": "build_shipyard",
		"title": "ERSTES GEBÄUDE",
		"text": "Öffne [P] PLANETEN-DOSSIER, wähle deinen Planeten und drücke BAUEN auf dem „Orbitalen Werft-Design“ (Kategorie INFRASTRUKTUR).",
		"predicate": Callable(self, "_shipyard_building"),
		"target": "planet",
	})
	_steps.append({
		"id": "workshop",
		"title": "WERKSTATT & SCHIFF",
		"text": "Öffne [W] WERKSTATT, kaufe Teile (Hülle, Antrieb, Schild, Scanner), wähle sie in der Montage und drücke KOMBINIEREN.",
		"predicate": Callable(self, "_ship_in_build"),
		"target": "button:WERKSTATT",
	})
	_steps.append({
		"id": "scout",
		"title": "FORSCHUNGSSCHIFF STARTEN",
		"text": "In der WERKSTATT unten: Startplanet + unbekannter Nachbar wählen und FORSCHUNGSSCHIFF STARTEN drücken.",
		"predicate": Callable(self, "_scout_launched"),
		"target": "button:WERKSTATT",
	})
	_steps.append({
		"id": "done",
		"title": "BEREIT FÜR DIE STERNE",
		"text": "Geschafft! Erkunde weitere Welten, sammle Ressourcen und erweitere deine Flotte. Viel Erfolg, Commander.",
		"predicate": null,
		"target": "",
	})

func _present_step() -> void:
	if _step_index >= _steps.size() or not _active:
		_finish()
		return
	var step: Dictionary = _steps[_step_index]
	_title_label.text = String(step.get("title", ""))
	_text_label.text = String(step.get("text", ""))
	_counter_label.text = "Schritt %d / %d" % [_step_index + 1, _steps.size()]
	_marker_target_valid = false
	_marker_target = Vector2.ZERO
	if String(step.get("target", "")) == "planet":
		var target_planet := _target_planet()
		if target_planet != null and is_instance_valid(target_planet):
			_marker_target = _world_to_screen(target_planet.global_position)
			_marker_target_valid = true
	elif String(step.get("target", "")).begins_with("button:"):
		var button := _find_launcher_button(String(step.get("target", "")).get_slice(":", 1))
		if button != null and is_instance_valid(button):
			var rect: Rect2 = button.get_global_rect()
			_marker_target = rect.get_center()
			_marker_target_valid = true
	_marker.queue_redraw()

func _on_weiter_pressed() -> void:
	_step_index += 1
	_present_step()

func _finish() -> void:
	_active = false
	hide_overlay()

# ── Prädikate ──────────────────────────────────────────────────────────

func _homeworld_selected() -> bool:
	if _planet_network == null or not is_instance_valid(_planet_network):
		return false
	var ui: Node = _planet_network.get("_ui") if _planet_network.get("_ui") != null else null
	if ui == null or not ui.has_method("is_panel_visible"):
		return false
	return bool(ui.call("is_panel_visible"))

func _research_started() -> bool:
	if _state == null:
		return false
	return _state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction") or _state.research_in_progress(GameState.FACTION_PLAYER, &"shipyard_construction")

func _shipyard_building() -> bool:
	if _state == null:
		return false
	for planet in _planets_of(GameState.FACTION_PLAYER):
		if planet == null:
			continue
		var planet_id: StringName = planet.get("planet_id")
		if _state.has_planet_upgrade(planet_id, &"shipyard"):
			return true
		if _state.has_method("upgrade_build_in_progress") and _state.upgrade_build_in_progress(planet_id, &"shipyard"):
			return true
	return false

func _ship_in_build() -> bool:
	if _state == null:
		return false
	for planet in _planets_of(GameState.FACTION_PLAYER):
		if planet == null:
			continue
		if _state.has_method("get_ship_build_jobs") and not _state.get_ship_build_jobs(planet.get("planet_id")).is_empty():
			return true
		if _state.has_method("get_ship_assemblies") and not _state.get_ship_assemblies(planet.get("planet_id")).is_empty():
			return true
	return false

func _scout_launched() -> bool:
	if _state == null:
		return false
	if _state.has_method("get_research_ship_records"):
		var records: Array = _state.get_research_ship_records(GameState.FACTION_PLAYER)
		if not records.is_empty():
			return true
	for planet in _planets_of(GameState.FACTION_PLAYER):
		if planet == null:
			continue
		if _state.has_method("get_ship_assemblies") and not _state.get_ship_assemblies(planet.get("planet_id")).is_empty():
			return true
	return false

# ── Helfer ─────────────────────────────────────────────────────────────

func _target_planet() -> Node:
	for planet in _planets_of(GameState.FACTION_PLAYER):
		if planet != null:
			return planet
	return null

func _planets_of(faction: StringName) -> Array[Node]:
	var result: Array[Node] = []
	if get_tree() == null or _state == null:
		return result
	for node in get_tree().get_nodes_in_group("planets"):
		if node != null and is_instance_valid(node):
			var planet_id: StringName = node.get("planet_id") if node.get("planet_id") != null else &""
			if _state.faction_of(planet_id) == faction:
				result.append(node)
	return result

func _find_launcher_button(label: String) -> Control:
	if _planet_network == null:
		return null
	var layer: Node = _planet_network.get_node_or_null("DossierLauncher")
	if layer == null:
		return null
	var box: Node = layer.get_node_or_null("LauncherBox")
	if box == null:
		return null
	for child in box.get_children():
		if child is Button and String(child.text).to_upper() == label:
			return child as Control
	return null

func _world_to_screen(world_position: Vector2) -> Vector2:
	if _map_camera != null and is_instance_valid(_map_camera) and _map_camera.has_method("get_canvas_transform"):
		return _map_camera.get_canvas_transform() * world_position
	return world_position

func _draw_marker() -> void:
	if not _active or not _marker_target_valid:
		return
	var radius := 16.0 + 4.0 * sin(Time.get_ticks_msec() * 0.006)
	var color := _theme_config.branch_tech_color
	color.a = 0.9
	_marker.draw_arc(_marker_target, radius, 0.0, TAU, 48, color, 3.0, true)
	_marker.draw_arc(_marker_target, radius + 6.0, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.35), 2.0, true)

func _process(delta: float) -> void:
	if not _active:
		return
	_marker.queue_redraw()
	_poll_accumulator += delta
	if _poll_accumulator < POLL_INTERVAL:
		return
	_poll_accumulator = 0.0
	var step: Dictionary = _steps[_step_index] if _step_index < _steps.size() else {}
	var predicate: Variant = step.get("predicate", Callable())
	if predicate is Callable and predicate.is_valid() and bool(predicate.call()):
		_step_index += 1
		_present_step()
