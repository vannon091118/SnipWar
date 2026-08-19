extends Node2D

const _FlightTime := preload("res://scripts/flight_time.gd")
const _Dispatch := preload("res://scripts/dispatch.gd")
const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const DEFAULT_UI_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

@export var transit_config: TransitConfig = DEFAULT_CONFIG
@export var ui_theme_config: UIThemeConfig = DEFAULT_UI_THEME

@onready var _worker_manager: Node = get_parent().get_node("WorkerManager")
@onready var _navigation: NavigationField = get_parent().get_node("NavigationField")

var _planets: Array[Node2D] = []
var _routes: Dictionary = {}
var _active_planet: Node2D
var _destination_planets: Array[Node2D] = []
var _ui: PlanetNetworkUI
var _line_phase := 0.0

func _ready() -> void:
	for child in get_parent().get_children():
		if child is Node2D and child.get("layout_size") != null:
			_planets.append(child)
			child.planet_selected.connect(_on_planet_selected)
			child.worker_count_changed.connect(_on_worker_count_changed)
			child.workers_spawn_requested.connect(_on_workers_spawn_requested)
	_create_ui.call_deferred()

func _create_ui() -> void:
	_ui = PlanetNetworkUI.new()
	add_child(_ui)
	_ui.setup(_planets, ui_theme_config)
	_ui.panel_visibility_changed.connect(_on_panel_visibility_changed)
	_ui.destination_selected.connect(_on_destination_selected)
	_ui.amount_changed.connect(_on_amount_changed)
	_ui.send_pressed.connect(_on_send_pressed)

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
		var route_alpha := 0.82 + sin(_line_phase * 2.0) * 0.08
		var route_color := Color(1.0, 0.85, 0.2, route_alpha)
		for index in range(route_path.size() - 1):
			draw_line(to_local(route_path[index]), to_local(route_path[index + 1]), route_color, 3.0, true)

func _on_panel_visibility_changed(_visible: bool) -> void:
	queue_redraw()

func _on_workers_spawn_requested(source: Node2D, amount: int) -> void:
	_worker_manager.call("_spawn_clusters", source, amount)

func _on_planet_selected(planet: Node2D) -> void:
	if not is_instance_valid(_ui):
		return
	_active_planet = planet
	_destination_planets = get_route_destinations(planet)
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
	var seconds := _FlightTime.seconds_for(distance, _ui.selected_amount(), transit_config)
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
		_worker_manager.call("_dispatch_clusters", _active_planet, destination, _ui.selected_amount(), get_route_path(_active_planet, destination))

func get_ui() -> PlanetNetworkUI:
	return _ui

func get_line_phase() -> float:
	return _line_phase

func get_route_path(source: Node2D, destination: Node2D) -> Array[Vector2]:
	if is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]

func _path_distance(path: Array[Vector2]) -> float:
	var distance := 0.0
	for index in range(path.size() - 1):
		distance += path[index].distance_to(path[index + 1])
	return distance

func get_destination(source: Node2D) -> Node2D:
	var selected = _routes.get(source)
	var allowed_destinations := get_route_destinations(source)
	if selected != null and is_instance_valid(selected) and allowed_destinations.has(selected):
		return selected as Node2D
	var neighbors := get_neighbors(source)
	return neighbors[0] if not neighbors.is_empty() else null

func get_route_destinations(source: Node2D) -> Array[Node2D]:
	var world_config: WorldConfig = get_parent().get("world_config") as WorldConfig
	if world_config != null and world_config.route_mode == WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY:
		return get_neighbors(source)
	var result: Array[Node2D] = []
	for destination in _planets:
		if destination != source:
			result.append(destination)
	return result

func get_neighbors(planet: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var slot: int = int(planet.get_meta("layout_slot", -1))
	if slot < 0:
		return result
	var world_config: WorldConfig = get_parent().get("world_config") as WorldConfig
	var columns: int = maxi(1, world_config.columns if world_config != null else 1)
	var row: int = floori(float(slot) / float(columns))
	var column: int = slot % columns
	for other in _planets:
		if other == planet:
			continue
		var other_slot: int = int(other.get_meta("layout_slot", -1))
		if other_slot < 0:
			continue
		var other_row: int = floori(float(other_slot) / float(columns))
		var other_column: int = other_slot % columns
		if absi(row - other_row) + absi(column - other_column) == 1:
			result.append(other)
	return result
