class_name TechResearchView
extends RefCounted

## Manages global technology research cards, prerequisites, and live research countdowns.

var _theme_config: UIThemeConfig
var _ship_manager: ShipManager
var _research_countdown_labels: Array[Label] = []
var _research_progress_bars: Array[ProgressBar] = []

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig) -> void:
	_ship_manager = ship_manager
	_theme_config = theme_config

func clear_countdowns() -> void:
	_research_countdown_labels.clear()
	_research_progress_bars.clear()

func build_research_section(container: VBoxContainer, category: StringName, state: Node, on_refresh_callback: Callable, note: String = "") -> void:
	if container == null or _ship_manager == null or state == null:
		return
	var catalog: TechnologyCatalog = _ship_manager.get_technology_catalog()
	if catalog == null:
		return
	if not note.is_empty():
		container.add_child(UIBaseUtils.make_label(note, _theme_config.muted_text_color, _theme_config.small_font_size))
	var entries := catalog.for_category(category)
	if entries.is_empty():
		container.add_child(UIBaseUtils.make_label("Keine Technologien verfügbar.", _theme_config.muted_text_color, _theme_config.body_font_size))
		return
	for technology in entries:
		if technology.requires_discovery and not state.has_scanned_planet(GameState.FACTION_PLAYER):
			continue
		container.add_child(_research_row(technology, state, on_refresh_callback))

func update_countdowns(state: Node) -> void:
	if state == null:
		return
	for label in _research_countdown_labels:
		if label == null or not is_instance_valid(label):
			continue
		var technology_id: StringName = label.get_meta("technology_id", &"") as StringName
		if state.research_in_progress(GameState.FACTION_PLAYER, technology_id):
			var remaining: float = state.research_remaining(GameState.FACTION_PLAYER, technology_id)
			var total_time: float = float(label.get_meta("total_time", 0.0))
			label.text = "IN FORSCHUNG (%.0f s · %d%%)" % [remaining, _progress_percent(total_time, remaining)]
	for progress in _research_progress_bars:
		if progress == null or not is_instance_valid(progress):
			continue
		var technology_id: StringName = progress.get_meta("technology_id", &"") as StringName
		if state.research_in_progress(GameState.FACTION_PLAYER, technology_id):
			var remaining: float = state.research_remaining(GameState.FACTION_PLAYER, technology_id)
			var total_time: float = float(progress.get_meta("total_time", 0.0))
			progress.value = clampf(total_time - remaining, 0.0, total_time)

func _research_row(technology: TechnologyDefinition, state: Node, on_refresh_callback: Callable) -> Control:
	var researched: bool = state.has_technology(GameState.FACTION_PLAYER, technology.id)
	var in_progress: bool = state.research_in_progress(GameState.FACTION_PLAYER, technology.id)
	var can_research: bool = state.can_research_technology(GameState.FACTION_PLAYER, technology.id, _ship_manager.get_technology_catalog())
	var remaining: float = state.research_remaining(GameState.FACTION_PLAYER, technology.id) if in_progress else 0.0
	var status_text: String
	if researched:
		status_text = "FREIGESCHALTET"
	elif in_progress:
		status_text = "IN FORSCHUNG (%.0f s · %d%%)" % [remaining, _progress_percent(technology.research_time, remaining)]
	elif can_research:
		status_text = "Kosten: %d %s" % [technology.cost_amount, String(technology.cost_resource)]
	else:
		status_text = "Gesperrt (Kosten/Voraussetzung fehlt)"
	return _technology_card(
		technology,
		status_text,
		researched or in_progress or not can_research,
		in_progress,
		technology.research_time,
		remaining,
		func():
			if state != null and _ship_manager != null:
				state.research_technology(GameState.FACTION_PLAYER, technology.id, _ship_manager.get_technology_catalog())
			if on_refresh_callback.is_valid():
				on_refresh_callback.call()
	)

func _technology_card(technology: TechnologyDefinition, status_text: String, disabled: bool, in_progress: bool, total_time: float, remaining: float, pressed: Callable) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override(
		"panel",
		UIBaseUtils.style_box(_theme_config, _theme_config.card_background, Color.TRANSPARENT, _theme_config.panel_border_width, _theme_config.panel_corner_radius)
	)
	row.tooltip_text = technology.description
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _theme_config.card_padding)
	content.add_child(_technology_icon(technology))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIBaseUtils.make_label(technology.display_name, _theme_config.heading_text_color, _theme_config.body_font_size))
	box.add_child(UIBaseUtils.make_label(technology.description, _theme_config.muted_text_color, _theme_config.small_font_size))
	var prerequisite_text: String = _technology_prerequisite_text(technology)
	if not prerequisite_text.is_empty():
		box.add_child(UIBaseUtils.make_label(prerequisite_text, _theme_config.secondary_text_color, _theme_config.small_font_size))
	box.add_child(UIBaseUtils.make_label(technology.mechanic_description, _theme_config.accent_text_color, _theme_config.small_font_size))
	var status_label := UIBaseUtils.make_label(status_text, _theme_config.accent_text_color, _theme_config.small_font_size)
	status_label.set_meta("technology_id", technology.id)
	status_label.set_meta("total_time", total_time)
	_research_countdown_labels.append(status_label)
	box.add_child(status_label)
	var progress := ProgressBar.new()
	progress.name = "ResearchProgress"
	progress.custom_minimum_size = Vector2(0.0, 6.0)
	progress.min_value = 0.0
	progress.max_value = maxf(total_time, 1.0)
	progress.value = clampf(total_time - remaining, 0.0, progress.max_value)
	progress.show_percentage = false
	progress.visible = in_progress
	progress.set_meta("technology_id", technology.id)
	progress.set_meta("total_time", total_time)
	progress.tooltip_text = "Forschungsfortschritt"
	_research_progress_bars.append(progress)
	box.add_child(progress)
	var research_button := Button.new()
	research_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_button.text = "FORSCHEN"
	research_button.disabled = disabled
	if pressed.is_valid():
		research_button.pressed.connect(pressed)
	box.add_child(research_button)
	content.add_child(box)
	row.add_child(content)
	return row

func _technology_icon(technology: TechnologyDefinition) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(_theme_config.technology_icon_size, _theme_config.technology_icon_size)
	icon.texture = technology.visual_asset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _progress_percent(total_time: float, remaining: float) -> int:
	if total_time <= 0.0:
		return 100
	return int(round(clampf((total_time - remaining) / total_time, 0.0, 1.0) * 100.0))

func _technology_prerequisite_text(technology: TechnologyDefinition) -> String:
	if String(technology.prerequisite_tech_id).is_empty():
		return ""
	var prerequisite: TechnologyDefinition = _ship_manager.get_technology_catalog().resolve(technology.prerequisite_tech_id)
	if prerequisite == null:
		return "Voraussetzung: %s" % technology.prerequisite_tech_id
	return "Voraussetzung: %s" % prerequisite.display_name
