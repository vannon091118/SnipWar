class_name TechResearchShipView
extends RefCounted

## Manages persistent ResearchShip tasks and Worker Factory activation in the tech menu.

const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"

var _theme_config: UIThemeConfig
var _ship_manager: ShipManager
var scout_source: OptionButton
var scout_destination: OptionButton
var worker_source: OptionButton
var worker_button: Button

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig) -> void:
	_ship_manager = ship_manager
	_theme_config = theme_config

func build_research_ship_and_worker_section(
	container: VBoxContainer,
	state: Node,
	planets: Array[Planet],
	on_refresh_callback: Callable
) -> void:
	if container == null or _ship_manager == null or state == null:
		return

	container.add_child(UIBaseUtils.make_separator())
	container.add_child(UIBaseUtils.make_label("FORSCHUNGSSCHIFF", _theme_config.heading_text_color, _theme_config.section_font_size))
	container.add_child(UIBaseUtils.make_label("Das persistente Forschungsschiff fliegt zu unbekannten Nachbarn und bleibt nach der Ankunft erhalten.", _theme_config.muted_text_color, _theme_config.small_font_size))

	container.add_child(UIBaseUtils.make_label("Startplanet (eigene Werft)", _theme_config.secondary_text_color, _theme_config.small_font_size))
	scout_source = OptionButton.new()
	scout_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	populate_sources(scout_source, planets, state)
	scout_source.item_selected.connect(func(_idx: int): _on_scout_source_changed(state))
	container.add_child(scout_source)

	container.add_child(UIBaseUtils.make_label("Zielplanet (unbekannter Nachbar)", _theme_config.secondary_text_color, _theme_config.small_font_size))
	scout_destination = OptionButton.new()
	scout_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_source: Planet = selected_option_planet(scout_source)
	populate_destinations(scout_destination, selected_source, state)
	container.add_child(scout_destination)

	var start_button := Button.new()
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.text = "FORSCHUNGSSCHIFF STARTEN"
	var start_source: Planet = selected_option_planet(scout_source)
	var can_start: bool = start_source != null and scout_destination.item_count > 0 and _ship_manager.can_launch_research_ship(start_source)
	start_button.disabled = not can_start
	if not can_start:
		start_button.tooltip_text = "Ein verfügbares ResearchShip und ein unbekannter neutraler Nachbar sind erforderlich."
	start_button.pressed.connect(func():
		if scout_source == null or scout_destination == null:
			return
		var src: Planet = selected_option_planet(scout_source)
		var dest: Planet = selected_option_planet(scout_destination)
		if src != null and dest != null:
			_ship_manager.launch_research_ship(src, dest)
		if on_refresh_callback.is_valid():
			on_refresh_callback.call()
	)
	container.add_child(start_button)
	_build_task_queue_section(container, state, planets)

	container.add_child(UIBaseUtils.make_separator())
	container.add_child(UIBaseUtils.make_label("WORKER-FERTIGER", _theme_config.heading_text_color, _theme_config.section_font_size))
	container.add_child(UIBaseUtils.make_label("Nach dem ersten Scan und der Forschung wird hier die langsame Worker-Automatik aktiviert.", _theme_config.muted_text_color, _theme_config.small_font_size))
	worker_source = OptionButton.new()
	worker_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	populate_sources(worker_source, planets, state)
	container.add_child(worker_source)

	worker_button = Button.new()
	worker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worker_button.text = "WORKER-FERTIGER BAUEN"
	worker_button.pressed.connect(func():
		var src: Planet = selected_option_planet(worker_source)
		if src != null and _ship_manager.build_workers(src):
			if on_refresh_callback.is_valid():
				on_refresh_callback.call()
	)
	container.add_child(worker_button)
	refresh_worker_button()

func populate_sources(option: OptionButton, planets: Array[Planet], state: Node) -> void:
	if option == null:
		return
	option.clear()
	for planet in planets:
		if planet == null:
			continue
		var player_owned: bool = state.faction_of(planet.planet_id) == GameState.FACTION_PLAYER
		var has_shipyard: bool = state.has_planet_upgrade(planet.planet_id, SHIPYARD_UPGRADE_ID)
		var has_research_ship: bool = _has_research_ship_at(state, planet.planet_id)
		if player_owned and (has_shipyard or has_research_ship):
			option.add_item(planet.name)
			option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func populate_destinations(option: OptionButton, source: Planet, state: Node) -> void:
	if option == null:
		return
	option.clear()
	if source != null and _ship_manager != null:
		for planet in _ship_manager.get_scan_destinations(source):
			if planet.get_faction() == GameState.FACTION_NEUTRAL and not state.is_known(planet.planet_id, GameState.FACTION_PLAYER):
				option.add_item(planet.name)
				option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0

func selected_option_planet(option: OptionButton) -> Planet:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return null
	return option.get_item_metadata(option.selected) as Planet

func refresh_worker_button() -> void:
	if worker_button == null:
		return
	var source: Planet = selected_option_planet(worker_source)
	worker_button.disabled = source == null or not _ship_manager.can_build_workers(source)
	if source == null:
		worker_button.tooltip_text = "Eigene Werft und Worker-Automatik nach einem Scan erforderlich."
	else:
		worker_button.tooltip_text = "Bauplätze: %d" % source.get_build_slot_count()

func _build_task_queue_section(container: VBoxContainer, state: Node, planets: Array[Planet]) -> void:
	container.add_child(UIBaseUtils.make_label("TASK-QUEUE", _theme_config.heading_text_color, _theme_config.section_font_size))
	var records: Array[Dictionary] = state.get_research_ship_records(GameState.FACTION_PLAYER) if state.has_method("get_research_ship_records") else []
	if records.is_empty():
		container.add_child(UIBaseUtils.make_label("Kein Forschungsschiff registriert.", _theme_config.muted_text_color, _theme_config.small_font_size))
		return
	for record in records:
		var ship_status: String = String(record.get("status", &"idle")).to_upper()
		var location: String = String(record.get("current_planet_id", &"—"))
		container.add_child(UIBaseUtils.make_label("ResearchShip %s · %s · %s" % [String(record.get("ship_id", &"")), ship_status, location], _theme_config.secondary_text_color, _theme_config.small_font_size))
	var missions: Array[Dictionary] = state.get_research_missions(GameState.FACTION_PLAYER) if state.has_method("get_research_missions") else []
	for mission in missions:
		var remaining: float = float(mission.get("remaining", 0.0))
		var duration: float = maxf(float(mission.get("duration", 1.0)), 0.01)
		var progress := ProgressBar.new()
		progress.name = "ResearchTaskProgress"
		progress.max_value = duration
		progress.value = duration - remaining
		progress.show_percentage = false
		progress.tooltip_text = "%s · %s · %.1f s" % [String(mission.get("task_type", &"task")), String(mission.get("target_planet_id", &"")), remaining]
		container.add_child(progress)
	var idle_record: Dictionary = {}
	for record in records:
		if record.get("status", &"") == &"idle" and String(record.get("active_mission_id", &"")).is_empty():
			idle_record = record
			break
	if idle_record.is_empty():
		return
	var target: StringName = idle_record.get("current_planet_id", &"") as StringName
	var task_type := OptionButton.new()
	task_type.name = "ResearchTaskType"
	task_type.add_item("SCAN", 0)
	task_type.add_item("EXPLORE", 1)
	task_type.set_item_metadata(0, &"scan")
	task_type.set_item_metadata(1, &"explore")
	container.add_child(task_type)
	var add_task := Button.new()
	add_task.name = "QueueResearchTask"
	add_task.text = "TASK AM AKTUELLEN PLANETEN EINREIHEN"
	add_task.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_task.pressed.connect(func():
		var task_id: StringName = task_type.get_item_metadata(task_type.selected) as StringName
		state.queue_research_mission(GameState.FACTION_PLAYER, target, task_id, 2.0)
	)
	container.add_child(add_task)

func _has_research_ship_at(state: Node, planet_id: StringName) -> bool:
	if state == null or not state.has_method("get_research_ship_records"):
		return false
	for record in state.get_research_ship_records(GameState.FACTION_PLAYER):
		if record.get("current_planet_id", &"") == planet_id and record.get("status", &"") == &"idle":
			return true
	return false

func _on_scout_source_changed(state: Node) -> void:
	if scout_destination != null and state != null:
		populate_destinations(scout_destination, selected_option_planet(scout_source), state)
