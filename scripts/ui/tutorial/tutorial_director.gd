class_name TutorialDirector
extends CanvasLayer

## Reines Onboarding: führt den Spieler Schritt für Schritt durch die erste
## Partie (Kamera → Planetenwahl → Forschung → Bau → Werkstatt → Scout).
## Das Tutorial ist ausschließlich präsentativ — es startet, erkennt, wartet
## oder vollzieht NICHTS im Hintergrund. Jeder Schritt zeigt eine Flyover-Karte
## plus Ziel-Marker (Weltposition oder UI-Button) und erklärt, was der Spieler
## tun soll; weiter geht es ausschließlich über den WEITER-Button.
## TUTORIAL-Button im DossierLauncher startet neu. Es gibt bewusst KEINE
## vordefinierten Test-Szenarien für den Ablauf — die MCP-Agenten entdecken die
## Oberfläche selbst und erweitern ihre Bibliothek über das Playthrough-Archiv.


var _theme_config: UIThemeConfig
var _planet_network: Node
var _ship_manager: Node
var _map_camera: Node
var _state: Node
var _steps: Array = []
var _step_index := 0
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
var _marker_draw_pos := Vector2.ZERO
var _marker_offscreen := false
var _open_pending_label := ""
var _open_pending_delay := 0.0
var _scrolled_steps: Dictionary = {}

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
	_scrolled_steps.clear()
	_open_pending_label = ""
	_open_pending_delay = 0.0
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
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Flyover: Panel-Body schluckt keine Klicks; WEITER/ÜBERSPRINGEN behalten ihren eigenen Filter
	_card.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.texture_style_box(_theme_config, _theme_config.modal_background_texture, _theme_config.panel_background, float(_theme_config.card_padding))
	)
	# Flyover card: floats near the current step's target (planet/button)
	# instead of a fixed dialog zone. Position is managed per frame by
	# _position_card() and clamped to the viewport, size follows content.
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.position = Vector2(320.0, 380.0)
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
	_text_label.custom_minimum_size = Vector2(320.0, 0.0)
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
	_marker_offscreen = false
	_marker_draw_pos = Vector2.ZERO

# ── Schritte ───────────────────────────────────────────────────────────

func _build_steps() -> void:
	_steps = []
	_steps.append({
		"id": "camera",
		"title": "WILLKOMMEN IM PAPIERKOSMOS",
		"text": "Deine Heimatwelt trägt den grünen Ring. Kamera: [W A S D], Zoom: Mausrad. Mehr braucht es nicht — Stickmen reisen leicht.",
		"target": "planet",
		"width_min": 340.0,
	})
	_steps.append({
		"id": "select_homeworld",
		"title": "HEIMATWELT WÄHLEN",
		"text": "Klick die grün geringelte Welt an. Das Planeten-Panel öffnet sich rechts — dort laufen Missionsversand und deine existenziellen Entscheidungen zusammen.",
		"target": "planet",
		"width_min": 340.0,
	})
	_steps.append({
		"id": "research",
		"title": "DIREKT FORSCHEN",
		"text": "Wir haben den Forschungsbaum aufgeklappt und zur nächsten Bubble gescrollt. Grüner Rahmen = klickbar. EIN Klick startet die Forschung sofort; der Fortschritt füllt sich live in der Bubble. Keine Bestätigungsfalle, versprochen.",
		"target": "",
		"open": "FORSCHUNG",
		"width_min": 380.0,
	})
	_steps.append({
		"id": "open_dossier",
		"title": "DOSSIER AUFKLAPPEN",
		"text": "[PLANET] ist offen: Bau, Hangar und planetare Forschung stecken in deinem Aktenberg. Blättern lohnt sich — Papier lügt nicht. Meistens.",
		"target": "",
		"open": "PLANET",
		"width_min": 340.0,
	})
	_steps.append({
		"id": "build_shipyard",
		"title": "WERFT BAUEN",
		"text": "Im Block MILITARY wartet die Orbitale Werft (20 Biomasse · 5 Credits). BAUEN drücken — der Timer läuft von allein, wir arbeiten hier schließlich professionell.",
		"target": "",
		"open": "PLANET",
		"width_min": 350.0,
	})
	_steps.append({
		"id": "workshop",
		"title": "WERKSTATT: TEILE MONTIEREN",
		"text": "Hülle, Antrieb, Schild, Scanner kaufen, in der Montage wählen, KOMBINIEREN drücken. Vier Teile, ein Schiff — Flottenbau war nie ehrlicher.",
		"target": "",
		"open": "WERKSTATT",
		"width_min": 360.0,
	})
	_steps.append({
		"id": "scout",
		"title": "FORSCHUNGSSCHIFF STARTEN",
		"text": "Ganz unten in der Werkstatt: Startplanet wählen, unbekannten Nachbarn ins Visier nehmen, FORSCHUNGSSCHIFF STARTEN. Sag den Nachbarn hallo für uns.",
		"target": "",
		"open": "WERKSTATT",
		"width_min": 350.0,
	})
	_steps.append({
		"id": "done",
		"title": "READY, COMMANDER",
		"text": "Fertig. Weitere Welten, mehr Ressourcen, größere Flotte — der Rand der Galaxie schreibt das alles in deine Akte. Das X oben rechts schließt dieses Fenster hier.",
		"target": "",
		"width_min": 320.0,
	})


func _present_step() -> void:
	if _step_index >= _steps.size() or not _active:
		_finish()
		return
	var step: Dictionary = _steps[_step_index]
	_title_label.text = String(step.get("title", ""))
	_text_label.text = String(step.get("text", ""))
	var width_min := float(step.get("width_min", 320.0))
	_text_label.custom_minimum_size.x = width_min - 36.0
	_counter_label.text = "Schritt %d / %d" % [_step_index + 1, _steps.size()]
	_refresh_marker_target()
	_marker.queue_redraw()
	_schedule_open(step)

func _on_weiter_pressed() -> void:
	_step_index += 1
	_present_step()

## Oeffnet das zum Schritt gehoerende Menue (Flyover-Onboarding): Der Schritt
## erklaert das Ziel dort, wo es liegt -- nicht als statisches Dialogfeld.
func _schedule_open(step: Dictionary) -> void:
	var label := String(step.get("open", ""))
	if label.is_empty():
		return
	# Launcher-Buttons oeffnen nur (idempotent, kein Toggle) — daher darf der
	# Schritt sie immer druecken. Ein zwischenzeitlich manuell geschlossenes
	# Menue wird so zuverlaessig wieder geoeffnet; kein Client-Sync-Status.
	_open_pending_label = label
	_open_pending_delay = 0.3

func _press_launcher(label: String) -> void:
	var button := _find_launcher_button(label)
	if button is Button and is_instance_valid(button):
		(button as Button).pressed.emit()

func _current_step_id() -> String:
	if _step_index >= _steps.size():
		return ""
	return String(_steps[_step_index].get("id", ""))

## Fuer den Forschungsschritt: TreeScroll auf die erste klickbare Bubble
## zentrieren, damit direkte Ausfuehrung tatsaechlich vor Augen steht.
func _try_research_auto_scroll() -> void:
	if _current_step_id() != "research" or _scrolled_steps.has("research"):
		return
	var scroll := _find_tree_scroll()
	if scroll == null or not scroll.is_visible_in_tree():
		return
	for child in scroll.get_children():
		if child is Control and String(child.name) == "TreeCanvas":
			var canvas := child as Control
			var decided := false
			for node in canvas.get_children():
				var button := node as Button
				if button == null or not String(node.name).begins_with("TechNode_") or button.disabled:
					continue
				var center: Vector2 = button.get_meta("tree_center", button.position + button.size * 0.5)
				var h_bar := scroll.get_h_scroll_bar()
				var v_bar := scroll.get_v_scroll_bar()
				scroll.scroll_horizontal = int(clampf(center.x - scroll.size.x * 0.5, 0.0, float(h_bar.max_value))) if h_bar != null else 0
				scroll.scroll_vertical = int(clampf(center.y - scroll.size.y * 0.5, 0.0, float(v_bar.max_value))) if v_bar != null else 0
				decided = true
				break
			if decided or canvas.get_child_count() > 0:
				_scrolled_steps["research"] = true
			return

func _find_tree_scroll() -> ScrollContainer:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.find_child("TreeScroll", true, false) as ScrollContainer

func _finish() -> void:
	_active = false
	hide_overlay()

# ── Helfer ─────────────────────────────────────────────────────────────

func _target_planet() -> Node:
	if get_tree() == null or _state == null:
		return null
	# Versprechen des Tutorials: Der Ring haengt an der HEIMATWELT -- nicht an
	# irgendeinem Spielerplaneten, falls mehrere registriert sind.
	var home_id: StringName = &""
	if _state.has_method("homeworld_for"):
		home_id = _state.homeworld_for(GameState.FACTION_PLAYER)
	if not home_id.is_empty():
		for node in get_tree().get_nodes_in_group("planets"):
			if node == null or not is_instance_valid(node):
				continue
			var pid: StringName = node.get("planet_id") if node.get("planet_id") != null else &""
			if pid == home_id:
				return node
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
	var dossier_launcher: Node = _planet_network.get_node_or_null("DossierLauncher")
	if dossier_launcher == null:
		return null
	var box: Node = dossier_launcher.get_node_or_null("LauncherBox")
	if box == null:
		return null
	for child in box.get_children():
		if child is Button and String(child.text).to_upper() == label:
			return child as Control
	return null

func _world_to_screen(world_position: Vector2) -> Vector2:
	# CanvasLayer controls live in viewport/screen coordinates. Use the
	# viewport's canvas transform rather than the camera node directly; this
	# keeps the marker aligned with the rendered planet when the camera zooms,
	# pans, or the window is resized.
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_canvas_transform() * world_position
	if _map_camera != null and is_instance_valid(_map_camera) and _map_camera.has_method("get_canvas_transform"):
		return _map_camera.get_canvas_transform() * world_position
	return world_position

## Re-resolves the current step's target to its live screen position, so the
## marker ring (planet) or highlight (button) follows camera motion.
func _refresh_marker_target() -> void:
	var step: Dictionary = _steps[_step_index] if _step_index < _steps.size() else {}
	_marker_target_valid = false
	_marker_offscreen = false
	_marker_draw_pos = Vector2.ZERO
	_marker_target = Vector2.ZERO
	var target_text := String(step.get("target", ""))
	var point_valid := false
	if target_text == "planet":
		var target_planet := _target_planet()
		if target_planet != null and is_instance_valid(target_planet):
			_marker_target = _world_to_screen(target_planet.global_position)
			point_valid = true
	elif target_text.begins_with("button:"):
		var button := _find_launcher_button(String(target_text).get_slice(":", 1))
		if button != null and is_instance_valid(button):
			_marker_target = button.get_global_rect().get_center()
			point_valid = true
	if not point_valid:
		return
	# Der Ring bleibt sichtbar, solange das Ziel existiert: Liegt es ausserhalb
	# des Viewports, klemmt der Marker an den Rand und zeigt per Pfeil dahin.
	var viewport_rect := get_viewport().get_visible_rect()
	_marker_offscreen = not viewport_rect.grow(-40.0).has_point(_marker_target)
	_marker_draw_pos = _marker_target.clamp(viewport_rect.position + Vector2(34.0, 34.0), viewport_rect.end - Vector2(34.0, 34.0))
	_marker_target_valid = true

## Flyover positioning: the card floats above the target when there is room,
## otherwise below it, always clamped inside the viewport.
func _position_card() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var card_size: Vector2 = _card.size
	if card_size.x <= 0.0 or card_size.y <= 0.0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin := 10.0
	var target: Vector2 = _marker_draw_pos if _marker_target_valid else Vector2(viewport_size.x * 0.5, viewport_size.y - 80.0)
	var position := Vector2(target.x - card_size.x * 0.5, target.y + 16.0)
	if target.y - card_size.y - margin >= 0.0:
		position.y = target.y - card_size.y - margin
	position.x = clampf(position.x, margin, maxf(margin, viewport_size.x - card_size.x - margin))
	position.y = clampf(position.y, margin, maxf(margin, viewport_size.y - card_size.y - margin))
	_card.position = position
	# _present_step fordert die schrittspezifische Breite an (_width_min);
	# hier wird nur bei schmalen Fenstern geschrumpft, sonst bleibt jede
	# Karte in ihrer eigenen Groesse statt uniform ueberzuscaliert.
	var requested := maxf(284.0, _text_label.custom_minimum_size.x)
	var allowed := maxf(240.0, viewport_size.x - margin * 2.0 - 36.0)
	_text_label.custom_minimum_size.x = minf(requested, allowed)

func _draw_marker() -> void:
	if not _active or not _marker_target_valid:
		return
	var t := Time.get_ticks_msec() * 0.001
	var radius := 16.0 + 3.0 * sin(t * 6.28)
	var color := Color(0.35, 0.85, 0.45)
	# Drehende Doppelschlinge: liest sich als Tutorial-Markierung, nicht als
	# Klick-Echo der Touch-/Maussteuerung.
	_marker.draw_arc(_marker_draw_pos, radius, t * 1.7, t * 1.7 + TAU * 0.72, 40, color, 3.0, true)
	_marker.draw_arc(_marker_draw_pos, radius + 6.0, -t * 1.1, -t * 1.1 + TAU * 0.55, 40, Color(color.r, color.g, color.b, 0.4), 2.0, true)
	if _marker_offscreen:
		var dir := _marker_target - _marker_draw_pos
		if dir.length_squared() > 1.0:
			dir = dir.normalized()
			var tip := _marker_draw_pos + dir * (radius + 18.0)
			var side := dir.orthogonal() * 9.0
			_marker.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14.0 + side, tip - dir * 14.0 - side]), color)

func _process(delta: float) -> void:
	if not _active:
		return
	# Flyover-Onboarding: Der Schritt oeffnet sein Menue selbst und richtet
	# den Blick aufs Ziel -- NUR Praesentation, keine Spiellogik.
	if _open_pending_delay > 0.0:
		_open_pending_delay -= delta
		if _open_pending_delay <= 0.0 and not _open_pending_label.is_empty():
			_press_launcher(_open_pending_label)
			_open_pending_label = ""
	_refresh_marker_target()
	_marker.queue_redraw()
	_position_card()
	_try_research_auto_scroll()
