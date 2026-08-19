class_name TechScoutView
extends RefCounted

## Manages Scout building, destination selection, and Worker Factory activation in the tech menu.

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

func build_scout_and_worker_section(
	container: VBoxContainer,
	state: Node,
	planets: Array[Planet],
	on_refresh_callback: Callable
) -> void:
	if container == null or _ship_manager == null or state == null:
		return

	container.add_child(UIBaseUtils.make_separator())
	container.add_child(UIBaseUtils.make_label("SCOUT BAUEN", _theme_config.heading_text_color, _theme_config.section_font_size))
	container.add_child(UIBaseUtils.make_label("Nur unbekannte benachbarte Gebiete können mit dem Scanner angeflogen werden.", _theme_config.muted_text_color, _theme_config.small_font_size))

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
	start_button.text = "SCOUT STARTEN"
	var start_source: Planet = selected_option_planet(scout_source)
	var can_start: bool = start_source != null and scout_destination.item_count > 0 and _ship_manager.can_build_scout(start_source)
	start_button.disabled = not can_start
	if not can_start:
		start_button.tooltip_text = "Start-Scout oder Werft, Scout-Rumpf, Scanner-Drohne, Material und ein freier Bauplatz sind erforderlich."
	start_button.pressed.connect(func():
		if scout_source == null or scout_destination == null:
			return
		var src: Planet = selected_option_planet(scout_source)
		var dest: Planet = selected_option_planet(scout_destination)
		if src != null and dest != null:
			_ship_manager.build_scout(src, dest)
		if on_refresh_callback.is_valid():
			on_refresh_callback.call()
	)
	container.add_child(start_button)

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
		var has_starter: bool = state.get_starter_scouts(GameState.FACTION_PLAYER) > 0
		if player_owned and (has_shipyard or has_starter):
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

func _on_scout_source_changed(state: Node) -> void:
	if scout_destination != null and state != null:
		populate_destinations(scout_destination, selected_option_planet(scout_source), state)
