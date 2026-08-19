extends Node2D

const _FlightTime := preload("res://scripts/flight_time.gd")
const _Dispatch := preload("res://scripts/dispatch.gd")
const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const DEFAULT_UI_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const PLANET_NETWORK_UI_SCENE: PackedScene = preload("res://scenes/ui/planet_network_ui.tscn")
const TECHNOLOGY_MENU_SCENE: PackedScene = preload("res://scenes/ui/technology_menu.tscn")
const MESSAGE_FEED_SCENE: PackedScene = preload("res://scenes/ui/message_feed.tscn")

@export var transit_config: TransitConfig = DEFAULT_CONFIG
@export var ui_theme_config: UIThemeConfig = DEFAULT_UI_THEME

@onready var _worker_manager: Node = get_parent().get_node("WorkerManager")
@onready var _navigation: NavigationField = get_parent().get_node("NavigationField")

var _planets: Array[Node2D] = []
var _routes: Dictionary = {}
var _active_planet: Node2D
var _destination_planets: Array[Node2D] = []
var _ui: PlanetNetworkUI
var _technology_menu: TechnologyMenu
var _message_feed: MessageFeed
var _line_phase := 0.0
var _neighbor_cache: Dictionary = {}
var _neighbor_cache_valid := false

func _ready() -> void:
	if get_parent() != null and get_parent().has_signal("layout_completed"):
		var parent_node: Node = get_parent()
		if not parent_node.is_connected("layout_completed", Callable(self, "_on_layout_completed")):
			parent_node.connect("layout_completed", Callable(self, "_on_layout_completed"))
	for child in get_parent().get_children():
		if child is Node2D and child.get("layout_size") != null:
			_planets.append(child)
			child.planet_selected.connect(_on_planet_selected)
			child.worker_count_changed.connect(_on_worker_count_changed)
			child.workers_spawn_requested.connect(_on_workers_spawn_requested)
	if not transit_config_identity_valid():
		push_error("PlanetNetwork and WorkerManager must share the same TransitConfig resource")
	_create_ui.call_deferred()

func _on_layout_completed(_planets: Array = []) -> void:
	invalidate_neighbor_cache()

func _create_ui() -> void:
	_ui = PLANET_NETWORK_UI_SCENE.instantiate() as PlanetNetworkUI
	add_child(_ui)
	_ui.setup(_planets, ui_theme_config)
	_ui.panel_visibility_changed.connect(_on_panel_visibility_changed)
	_ui.destination_selected.connect(_on_destination_selected)
	_ui.mission_selected.connect(_on_mission_selected)
	_ui.amount_changed.connect(_on_amount_changed)
	_ui.send_pressed.connect(_on_send_pressed)
	_create_technology_menu.call_deferred()
	_create_message_feed.call_deferred()

func _process(delta: float) -> void:
	if _active_planet != null and is_instance_valid(_ui) and _ui.is_panel_visible():
		_line_phase += delta
		queue_redraw()

func _draw() -> void:
	if _active_planet == null or not is_instance_valid(_ui) or not _ui.is_panel_visible():
		return
	var destination := get_destination(_active_planet)
	if destination != null:
		var route_path := get_route_path(_active_planet, destination)
		var theme: UIThemeConfig = ui_theme_config if ui_theme_config != null else DEFAULT_UI_THEME
		var route_alpha: float = clampf(theme.route_line_alpha + sin(_line_phase * theme.route_line_pulse_speed) * theme.route_line_pulse_alpha, 0.0, 1.0)
		var route_color := theme.route_line_color
		route_color.a = route_alpha
		for index in range(route_path.size() - 1):
			draw_line(to_local(route_path[index]), to_local(route_path[index + 1]), route_color, theme.route_line_width, true)

func _create_technology_menu() -> void:
	var ship_manager: ShipManager = get_parent().get_node_or_null("ShipManager") as ShipManager
	if ship_manager == null:
		return
	_technology_menu = TECHNOLOGY_MENU_SCENE.instantiate() as TechnologyMenu
	add_child(_technology_menu)
	_technology_menu.setup(ship_manager, ui_theme_config)
	_technology_menu.opened.connect(_on_technology_opened)

func _on_technology_opened() -> void:
	if is_instance_valid(_ui):
		_ui.close_panel()

func _create_message_feed() -> void:
	var event_log: Node = get_tree().root.get_node_or_null("EventLog")
	if event_log == null:
		return
	_message_feed = MESSAGE_FEED_SCENE.instantiate() as MessageFeed
	add_child(_message_feed)
	_message_feed.setup(event_log, ui_theme_config)

func get_technology_menu() -> TechnologyMenu:
	return _technology_menu

func get_message_feed() -> MessageFeed:
	return _message_feed

func _on_panel_visibility_changed(visible: bool) -> void:
	if visible and is_instance_valid(_technology_menu):
		_technology_menu.close()
	queue_redraw()

func _on_workers_spawn_requested(source: Node2D, amount: int) -> void:
	_worker_manager.call("_spawn_clusters", source, amount)

func _on_planet_selected(planet: Node2D) -> void:
	if not is_instance_valid(_ui):
		return
	_active_planet = planet
	_destination_planets = get_mission_destinations(planet, _ui.selected_mission_type())
	var default_destination := get_destination(planet)
	_ui.show_planet(planet, _destination_planets, default_destination)
	_update_selected_count()
	_refresh_slider_bounds()
	if _ui.has_selectable_amount():
		_ui.reset_amount()
		_update_preview()
	queue_redraw()

func _on_destination_selected(index: int) -> void:
	if _active_planet == null:
		return
	if index < 0 or index >= _destination_planets.size():
		return
	_routes[_active_planet] = _destination_planets[index]
	_update_preview()
	queue_redraw()

func _on_mission_selected(mission_type: StringName) -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	_destination_planets = get_mission_destinations(_active_planet, mission_type)
	var current_destination := get_destination(_active_planet)
	_ui.set_destinations(_destination_planets, current_destination)
	_update_preview()
	queue_redraw()

func _on_worker_count_changed(planet: Node2D, _count: int) -> void:
	if is_instance_valid(_ui):
		_ui.update_count(planet)
	if planet == _active_planet:
		_update_selected_count()
		_refresh_slider_bounds()

func _update_selected_count() -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	_ui.set_selected_count(int(_active_planet.get("worker_count")))

func _on_amount_changed(_value: float) -> void:
	_update_preview()
	queue_redraw()

func _update_preview() -> void:
	if not is_instance_valid(_ui):
		return
	if _active_planet == null or not _ui.has_selectable_amount():
		_ui.set_preview("Keine Einheiten verfügbar")
		return
	var destination := get_destination(_active_planet)
	if destination == null:
		_ui.set_preview("Kein Ziel verfügbar")
		return
	var route_path := get_route_path(_active_planet, destination)
	var distance := _path_distance(route_path)
	var speed_multiplier: float = (_active_planet as Planet).get_transfer_speed_multiplier()
	var seconds := _FlightTime.seconds_for(distance, _ui.selected_amount(), transit_config, speed_multiplier)
	_ui.set_preview("Flugzeit: %.1f s" % seconds)

func _refresh_slider_bounds() -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	var bounds := _Dispatch.amount_range(int(_active_planet.get("worker_count")))
	_ui.set_amount_bounds(bounds)
	_update_preview()

func _on_send_pressed() -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	var destination := get_destination(_active_planet)
	if destination != null:
		_worker_manager.call("_dispatch_clusters", _active_planet, destination, _ui.selected_amount(), get_route_path(_active_planet, destination), _ui.selected_mission_type())

func transit_config_identity_valid() -> bool:
	if _worker_manager == null or transit_config == null:
		return false
	var manager_config: TransitConfig = _worker_manager.get("transit_config") as TransitConfig
	return manager_config == transit_config

func get_ui() -> PlanetNetworkUI:
	return _ui

func get_line_phase() -> float:
	return _line_phase

func get_route_path(source: Node2D, destination: Node2D) -> Array[Vector2]:
	if is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]

func _path_distance(path: Array[Vector2]) -> float:
	return PathUtils.distance(path)

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func get_destination(source: Node2D) -> Node2D:
	var selected = _routes.get(source)
	var mission_type: StringName = _ui.selected_mission_type() if is_instance_valid(_ui) else GameState.MISSION_MILITARY
	var allowed_destinations := get_mission_destinations(source, mission_type)
	if selected != null and is_instance_valid(selected) and allowed_destinations.has(selected):
		return selected as Node2D
	return allowed_destinations[0] if not allowed_destinations.is_empty() else null

func get_route_destinations(source: Node2D) -> Array[Node2D]:
	var world_config: WorldConfig = get_parent().get("world_config") as WorldConfig
	if world_config != null and world_config.route_mode == WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY:
		return get_neighbors(source)
	var result: Array[Node2D] = []
	for destination in _planets:
		if destination != source:
			result.append(destination)
	return result

func get_mission_destinations(source: Node2D, mission_type: StringName) -> Array[Node2D]:
	var route_destinations: Array[Node2D] = get_route_destinations(source)
	if mission_type != GameState.MISSION_COLLECT:
		return route_destinations
	var state: Node = _game_state()
	if state == null or source == null:
		return []
	var result: Array[Node2D] = []
	var source_faction: StringName = (source as Planet).get_faction()
	for destination in route_destinations:
		var destination_planet: Planet = destination as Planet
		if destination_planet != null and destination_planet.get_faction() == GameState.FACTION_NEUTRAL and state.has_scanned_planet(source_faction, destination_planet.planet_id):
			result.append(destination)
	return result

func invalidate_neighbor_cache() -> void:
	_neighbor_cache.clear()
	_neighbor_cache_valid = false

func get_neighbors(planet: Node2D) -> Array[Node2D]:
	if not _neighbor_cache_valid:
		_build_neighbor_cache()
	var cached: Variant = _neighbor_cache.get(planet)
	if cached == null:
		return []
	return cached as Array[Node2D]

func _build_neighbor_cache() -> void:
	_neighbor_cache.clear()
	var world_config: WorldConfig = get_parent().get("world_config") as WorldConfig
	var columns: int = maxi(1, world_config.columns if world_config != null else 1)
	var slot_planets: Dictionary = {}
	for candidate in _planets:
		var candidate_slot: int = int(candidate.get_meta("layout_slot", -1))
		if candidate_slot >= 0:
			slot_planets[candidate_slot] = candidate
	for planet in _planets:
		var slot: int = int(planet.get_meta("layout_slot", -1))
		if slot < 0:
			continue
		var column: int = slot % columns
		var result: Array[Node2D] = []
		if column > 0 and slot_planets.has(slot - 1):
			result.append(slot_planets[slot - 1])
		if column < columns - 1 and slot_planets.has(slot + 1):
			result.append(slot_planets[slot + 1])
		if slot_planets.has(slot - columns):
			result.append(slot_planets[slot - columns])
		if slot_planets.has(slot + columns):
			result.append(slot_planets[slot + columns])
		_neighbor_cache[planet] = result
	_neighbor_cache_valid = true
