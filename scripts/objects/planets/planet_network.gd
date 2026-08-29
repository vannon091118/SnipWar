class_name PlanetNetwork
extends Node2D

## R-008: PlanetNetwork besitzt die Netzwerk-/State-Logik der Planetenszene:
## Routen, Nachbarschaft, Auswahl (SelectionService), Nebel (Fog of War),
## _process/_draw-Routen-Rendering und Dispatch. Die UI-Orchestrierung
## (Context-Menü, Dossiers, Hotkeys, Fleet-, Economy-, Message-, Tutorial-,
## Layout-Module, Dispatch-Vorschau) liegt in PlanetWorldUI (Kindknoten).
##
## Kompatibilitäts-Shims (dünn, delegieren an PlanetWorldUI) bleiben für
## Preflight-Constraints und Pause-Menü: _context_menu/_context_*,
## _economy_window, _build_context_menu_for, _on_context_action,
## _open_workshop_dossier, get_modal_coordinator/get_message_feed/
## get_fleet_overview, _connect_ship_selection.

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const DEFAULT_UI_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const PLANET_NETWORK_UI_SCENE: PackedScene = preload("res://scenes/ui/planet_network_ui.tscn")
const PLANET_WORLD_UI_SCRIPT: Script = preload("res://scripts/ui/world/planet_world_ui.gd")
const SELECTION_SERVICE_SCRIPT: Script = preload("res://scripts/objects/selection_service.gd")

@export var transit_config: TransitConfig = DEFAULT_CONFIG
@export var ui_theme_config: UIThemeConfig = DEFAULT_UI_THEME

@onready var _worker_manager: Node = get_parent().get_node("WorkerManager")
@onready var _navigation: NavigationField = get_parent().get_node("NavigationField")

var _planets: Array[Node2D] = []
var _routes: Dictionary = {}
var _active_planet: Node2D
var _destination_planets: Array[Node2D] = []
var _ui: PlanetNetworkUI
var _world_ui: PlanetWorldUI
var _chunk_coordinator: ChunkCoordinator
var _map_camera: MapCamera
var _selection_service: SelectionService
var _line_phase := 0.0
var _neighbor_cache: Dictionary = {}
var _neighbor_cache_valid := false

# Context-menu item IDs and stable names used by tests/replay scripts.
const ACTION_OPEN: int = 0
const ACTION_FOCUS: int = 1
const ACTION_SEPARATOR_1: int = 2
const ACTION_ATTACK: int = 3
const ACTION_COLLECT: int = 4
const ACTION_COLONIZE: int = 5
const ACTION_SEPARATOR_2: int = 6
const ACTION_CLEAR_SELECTION: int = 7
const ACTION_COUNT: int = 8

# --- Kompatibilitäts-Shims auf PlanetWorldUI (Preflight/Replay greifen direkt
# auf network-Felder zu; die echte Logik lebt in PlanetWorldUI). ---

var _context_menu: PopupMenu:
	get:
		return _world_ui.get_context_menu() if _world_ui != null else null
var _context_disabled_reasons: Dictionary:
	get:
		return _world_ui.get_context_disabled_reasons() if _world_ui != null else {}
var _context_active_planet: Node2D:
	get:
		return _world_ui.get_context_active_planet() if _world_ui != null else null
	set(value):
		if _world_ui != null:
			_world_ui.set_context_active_planet(value)
var _economy_window: EconomyWindow:
	get:
		return _world_ui.get_economy_window() if _world_ui != null else null


func _ready() -> void:
	_resolve_service_references()
	if get_parent() != null and get_parent().has_signal("layout_completed"):
		var parent_node: Node = get_parent()
		if not parent_node.is_connected("layout_completed", Callable(self, "_on_layout_completed")):
			parent_node.connect("layout_completed", Callable(self, "_on_layout_completed"))
	_create_selection_service()
	for child in get_parent().get_children():
		if child is Node2D and child.get("layout_size") != null:
			_planets.append(child)
			_connect_planet_signals(child)
	# Connect to the field-owned coordinator when infinite world mode is active.
	if _chunk_coordinator != null and not _chunk_coordinator.planet_added.is_connected(_on_planet_added):
		_chunk_coordinator.planet_added.connect(_on_planet_added)
		_chunk_coordinator.planet_removed.connect(_on_planet_removed)
	if not transit_config_identity_valid():
		push_error("PlanetNetwork and WorkerManager must share the same TransitConfig resource")
	_connect_fog_signals()
	_connect_map_camera.call_deferred()
	_connect_conflict_ships.call_deferred()
	_create_ui.call_deferred()
	_create_world_ui.call_deferred()
	_refresh_fog_of_war.call_deferred()


func _resolve_service_references() -> void:
	var field: SeededLayout = get_parent() as SeededLayout
	if field == null:
		return
	_chunk_coordinator = field.get_chunk_coordinator()
	var background: Node = field.get_parent()
	if background != null:
		_map_camera = background.get_node_or_null("MapCamera") as MapCamera


func _on_layout_completed(_unused_planets: Array = []) -> void:
	invalidate_neighbor_cache()
	_refresh_fog_of_war()


## Extracted signal-connection helper used by both _ready() and
## _on_planet_added() to avoid duplicate connection logic.
func _connect_planet_signals(planet: Node2D) -> void:
	if not planet.planet_selection_requested.is_connected(_on_planet_selection_requested):
		planet.planet_selection_requested.connect(_on_planet_selection_requested)
	if not planet.planet_context_requested.is_connected(_on_planet_context_requested):
		planet.planet_context_requested.connect(_on_planet_context_requested)
	if not planet.worker_count_changed.is_connected(_on_worker_count_changed):
		planet.worker_count_changed.connect(_on_worker_count_changed)
	if not planet.workers_spawn_requested.is_connected(_on_workers_spawn_requested):
		planet.workers_spawn_requested.connect(_on_workers_spawn_requested)
	if not planet.planet_hovered.is_connected(_on_planet_hovered):
		planet.planet_hovered.connect(_on_planet_hovered)
	if not planet.planet_unhovered.is_connected(_on_planet_unhovered):
		planet.planet_unhovered.connect(_on_planet_unhovered)


func _on_planet_added(planet: Planet) -> void:
	if not _planets.has(planet):
		_planets.append(planet)
		_connect_planet_signals(planet)
	if is_instance_valid(_ui):
		_ui.update_planets(_planets)
	_refresh_fog_of_war()


func _on_planet_removed(planet: Planet) -> void:
	_planets.erase(planet)
	if is_instance_valid(_ui):
		_ui.update_planets(_planets)


# --- Selection service ---


func _create_selection_service() -> void:
	_selection_service = SELECTION_SERVICE_SCRIPT.new() as SelectionService
	_selection_service.name = "SelectionService"
	add_child(_selection_service)
	if not _selection_service.primary_changed.is_connected(_on_selection_primary_changed):
		_selection_service.primary_changed.connect(_on_selection_primary_changed)
	if not _selection_service.selection_changed.is_connected(_on_selection_group_changed):
		_selection_service.selection_changed.connect(_on_selection_group_changed)
	if not _selection_service.selection_count_changed.is_connected(_on_selection_count_changed):
		_selection_service.selection_count_changed.connect(_on_selection_count_changed)


# --- UI creation (Panel-UI + Welt-UI) ---


func _create_ui() -> void:
	_ui = PLANET_NETWORK_UI_SCENE.instantiate() as PlanetNetworkUI
	add_child(_ui)
	_ui.setup(_planets, ui_theme_config)
	_ui.panel_visibility_changed.connect(_on_panel_visibility_changed)
	_ui.destination_selected.connect(_on_destination_selected)
	_ui.mission_selected.connect(_on_mission_selected)
	_ui.amount_changed.connect(_on_amount_changed)
	_ui.send_pressed.connect(_on_send_pressed)
	if not _ui.clear_selection_requested.is_connected(_on_clear_selection_requested):
		_ui.clear_selection_requested.connect(_on_clear_selection_requested)
	if not _ui.economy_overview_requested.is_connected(_on_economy_overview_requested):
		_ui.economy_overview_requested.connect(_on_economy_overview_requested)
	if _ui.has_signal("build_requested") and not _ui.build_requested.is_connected(_on_build_requested):
		_ui.build_requested.connect(_on_build_requested)


## R-008: PlanetWorldUI rendert keine Netzwerk-Logik — es orchestriert nur
## UI-Module und delegiert Intents über die dokumentierten Entry-Points.
func _create_world_ui() -> void:
	if _world_ui != null:
		return
	_world_ui = PLANET_WORLD_UI_SCRIPT.new() as PlanetWorldUI
	_world_ui.name = "PlanetWorldUI"
	add_child(_world_ui)
	var field: SeededLayout = get_parent() as SeededLayout
	var ship_manager: Node = get_parent().get_node_or_null("ShipManager")
	var conflict_manager: Node = get_parent().get_node_or_null("ConflictManager")
	_world_ui.setup(
		self,
		field,
		_ui,
		_planets,
		_selection_service,
		_worker_manager,
		ship_manager,
		conflict_manager,
		_map_camera,
		ui_theme_config,
		transit_config
	)


func _on_clear_selection_requested() -> void:
	if _selection_service != null:
		_selection_service.clear()


func _process(delta: float) -> void:
	if _active_planet != null and is_instance_valid(_ui) and _ui.is_panel_visible():
		_line_phase += delta
		queue_redraw()


func _draw() -> void:
	if _active_planet == null or not is_instance_valid(_ui) or not _ui.is_panel_visible():
		return
	var destination := get_destination(_active_planet)
	if destination == null:
		return
	# Don't render the active route when the destination sits inside the fog
	# frontier: routing into hidden territory is information the player hasn't
	# earned and contradicts the field-of-view promise.
	var destination_planet: Planet = destination as Planet
	if destination_planet != null and destination_planet.get_fog_state() == Planet.FogState.FOG:
		return
	var route_path := get_route_path(_active_planet, destination)
	var theme: UIThemeConfig = ui_theme_config if ui_theme_config != null else DEFAULT_UI_THEME
	var route_alpha: float = clampf(theme.route_line_alpha + sin(_line_phase * theme.route_line_pulse_speed) * theme.route_line_pulse_alpha, 0.0, 1.0)
	var route_color := theme.route_line_color
	route_color.a = route_alpha
	for index in range(route_path.size() - 1):
		draw_line(to_local(route_path[index]), to_local(route_path[index + 1]), route_color, theme.route_line_width, true)


# --- Context-menu shims (Logik in PlanetWorldUI) ---


func _on_planet_context_requested(planet: Node2D, screen_position: Vector2) -> void:
	if _world_ui != null:
		_world_ui.show_context_menu(planet, screen_position)


func _build_context_menu_for(planet: Node2D) -> void:
	if _world_ui != null:
		_world_ui.build_context_menu_for(planet)


func _on_context_action(id: int) -> void:
	if _world_ui != null:
		_world_ui.on_context_action(id)


func _on_context_item_focused(id: int) -> void:
	if _world_ui != null:
		_world_ui.on_context_item_focused(id)


func _on_planet_hovered(planet: Node2D) -> void:
	if _world_ui != null:
		_world_ui.on_planet_hovered(planet)


func _on_planet_unhovered(_planet: Node2D) -> void:
	if _world_ui != null:
		_world_ui.on_planet_unhovered()


func _center_camera_on(planet: Node2D) -> void:
	if _map_camera == null or not is_instance_valid(_map_camera) or planet == null:
		return
	_map_camera.position = planet.global_position


func _open_mission_for_target(target: Node2D, mission_type: StringName) -> void:
	if _world_ui != null:
		_world_ui.open_mission_for_target(target, mission_type)


func _show_action_tooltip(item_id: int, anchor_position: Vector2) -> void:
	if _world_ui != null:
		_world_ui.show_action_tooltip(item_id, anchor_position)


func _is_neighbor(source: Node2D, target: Node2D) -> bool:
	if source == null or target == null:
		return false
	for neighbor in get_neighbors(source):
		if neighbor == target:
			return true
	return false


# --- Dossier/Economy/Fleet shims (Logik in PlanetWorldUI) ---


func _open_planet_dossier() -> void:
	if _world_ui != null:
		_world_ui.open_planet_dossier()


func _open_workshop_dossier() -> void:
	if _world_ui != null:
		_world_ui.open_workshop_dossier()


func _open_tech_tree_dossier() -> void:
	if _world_ui != null:
		_world_ui.open_tech_tree_dossier()


func _on_economy_overview_requested() -> void:
	if _world_ui != null:
		_world_ui.open_economy_module()


func _on_build_requested() -> void:
	if _world_ui != null:
		_world_ui.open_planet_dossier()


func _restart_tutorial() -> void:
	if _world_ui != null:
		_world_ui.restart_tutorial()


func get_fleet_overview() -> FleetOverview:
	return _world_ui.get_fleet_overview() if _world_ui != null else null


func get_modal_coordinator() -> ModalCoordinator:
	return _world_ui.get_modal_coordinator() if _world_ui != null else null


func get_message_feed() -> MessageFeed:
	return _world_ui.get_message_feed() if _world_ui != null else null


# --- Selection flow ---


func _on_planet_selection_requested(planet: Node2D, modifiers: Dictionary) -> void:
	if _selection_service == null:
		return
	_selection_service.handle_request(planet, modifiers)


func _on_selection_primary_changed(_planet: Node2D) -> void:
	var primary: Node2D = _selection_service.get_primary() if _selection_service != null else null
	if primary == null:
		_clear_active_planet()
		return
	_on_planet_selected(primary)


func _on_selection_group_changed(selection: Array[Node2D]) -> void:
	if _world_ui != null:
		_world_ui.on_selection_group_changed(selection)
	queue_redraw()


func _on_selection_count_changed(count: int) -> void:
	if _world_ui != null:
		_world_ui.set_selection_count(count)


func _clear_active_planet() -> void:
	if is_instance_valid(_active_planet):
		var previous: Planet = _active_planet as Planet
		if previous != null:
			previous.set_selected(false)
	_active_planet = null
	if is_instance_valid(_ui):
		_ui.close_panel()
	if _world_ui != null:
		_world_ui.close_panel()
	queue_redraw()


func get_selection_service() -> SelectionService:
	return _selection_service


func _on_planet_selected(planet: Node2D) -> void:
	if not is_instance_valid(_ui):
		return
	if is_instance_valid(_active_planet) and _active_planet != planet:
		var previous: Planet = _active_planet as Planet
		if previous != null:
			previous.set_selected(false)
	_active_planet = planet
	var selected_planet: Planet = planet as Planet
	if selected_planet != null:
		selected_planet.set_selected(true)
	_destination_planets = get_mission_destinations(planet, _ui.selected_mission_type())
	var default_destination := get_destination(planet)
	if _world_ui != null:
		_world_ui.on_planet_selected(planet, _destination_planets, default_destination)
	queue_redraw()


func _on_worker_count_changed(planet: Node2D, _count: int) -> void:
	if is_instance_valid(_ui):
		_ui.update_count(planet)
	if planet == _active_planet and _world_ui != null:
		_world_ui.refresh_selected_count()
		_world_ui.refresh_slider_bounds()


# --- Route / dispatch flow ---


func _on_destination_selected(index: int) -> void:
	if _active_planet == null:
		return
	if index < 0 or index >= _destination_planets.size():
		return
	_routes[_active_planet] = _destination_planets[index]
	if _world_ui != null:
		_world_ui.update_preview()
		_world_ui.refresh_dispatch_lock()
	queue_redraw()


func _on_mission_selected(mission_type: StringName) -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	_destination_planets = get_mission_destinations(_active_planet, mission_type)
	var current_destination := get_destination(_active_planet)
	_ui.set_destinations(_destination_planets, current_destination)
	if _world_ui != null:
		_world_ui.update_preview()
		_world_ui.refresh_dispatch_lock()
	queue_redraw()


func _on_amount_changed(_value: float) -> void:
	if _world_ui != null:
		_world_ui.update_preview()
	queue_redraw()


func _on_send_pressed() -> void:
	if _active_planet == null or not is_instance_valid(_ui):
		return
	if _dispatch_locked_for_destination():
		return
	var destination := get_destination(_active_planet)
	if destination != null:
		_worker_manager.call("_dispatch_clusters", _active_planet, destination, _ui.selected_amount(), get_route_path(_active_planet, destination), _ui.selected_mission_type())
		if _world_ui != null:
			_world_ui.refresh_dispatch_lock.call_deferred()


## Sprint 6 (S9): max one active dispatch order per planet. Disables the send
## button (and preview) while the selected destination already has a mission.
func _dispatch_locked_for_destination() -> bool:
	if _active_planet == null or not is_instance_valid(_ui) or _worker_manager == null:
		return false
	if not _worker_manager.has_method("has_active_order"):
		return false
	var destination := get_destination(_active_planet)
	if destination == null:
		return false
	var planet: Planet = destination as Planet
	if planet == null:
		return false
	return _worker_manager.has_active_order(planet.planet_id)


func transit_config_identity_valid() -> bool:
	if _worker_manager == null or transit_config == null:
		return false
	var manager_config: TransitConfig = _worker_manager.get("transit_config") as TransitConfig
	return manager_config == transit_config


func get_ui() -> PlanetNetworkUI:
	return _ui


func get_active_planet() -> Node2D:
	return _active_planet


func get_active_destinations() -> Array[Node2D]:
	return _destination_planets


func get_line_phase() -> float:
	return _line_phase


# --- Network queries ---


func get_ship_flight_preview(source: Planet, destination: Planet, ship_id: StringName) -> float:
	var conflict_manager: Node = get_parent().get_node_or_null("ConflictManager")
	if conflict_manager == null or not conflict_manager.has_method("preview_duration"):
		return 0.0
	return float(conflict_manager.call("preview_duration", source, destination, ship_id))


func get_route_path(source: Node2D, destination: Node2D) -> Array[Vector2]:
	if is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]


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
	# NavigationField is the single source of truth for adjacency — it exposes
	# the union of slot-grid edges AND K-nearest long-range edges. Rebuilding
	# the slot grid here would silently disagree with the routing graph the
	# moment NavigationField's growth contract kicks in.
	if not is_instance_valid(_navigation):
		_neighbor_cache_valid = true
		return
	for planet in _planets:
		var neighbors: Array[Node2D] = _navigation.get_neighbors_for_planet(planet)
		# Stable sort by neighbor index/id so the Set/seen-order in scripts
		# that iterate the cache stays deterministic across rebuilds.
		neighbors.sort_custom(func(a, b):
			var ai := int((a as Node).get_index())
			var bi := int((b as Node).get_index())
			if ai == bi:
				return String(a.name) < String(b.name)
			return ai < bi
		)
		_neighbor_cache[planet] = neighbors
	_neighbor_cache_valid = true


# --- Fog of war ---


func _connect_fog_signals() -> void:
	var state: Node = _game_state()
	if state == null:
		return
	if not state.faction_changed.is_connected(_on_faction_changed):
		state.faction_changed.connect(_on_faction_changed)
	if not state.planet_discovered.is_connected(_on_planet_discovered):
		state.planet_discovered.connect(_on_planet_discovered)
	if not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)


func _on_faction_changed(_planet_id: StringName, _old_faction: StringName, _new_faction: StringName) -> void:
	_refresh_fog_of_war()


func _on_planet_discovered(_faction: StringName, _planet_id: StringName) -> void:
	_refresh_fog_of_war()


func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	_refresh_fog_of_war()


## Recomputes the player's fog-of-war frontier: own/known planets are fully
## visible, their unknown neighbors are dimmed, and everything else is hidden.
## The underlying network is fixed per seed; this only changes what is revealed.
## In infinite world mode, iterates only active planets (from ChunkCoordinator)
## to avoid scanning an unbounded set.
func _refresh_fog_of_war() -> void:
	var state: Node = _game_state()
	if state == null:
		return
	var planets_to_check: Array = _chunk_coordinator.get_active_planets() if _chunk_coordinator != null and is_instance_valid(_chunk_coordinator) else _planets
	for planet in planets_to_check:
		var planet_node: Planet = planet as Planet
		if planet_node == null:
			continue
		if state.is_known(planet_node.planet_id, GameState.FACTION_PLAYER):
			planet_node.apply_fog(Planet.FogState.VISIBLE)
		elif _is_frontier_for_player(planet):
			planet_node.apply_fog(Planet.FogState.FRONTIER)
		else:
			planet_node.apply_fog(Planet.FogState.FOG)
	# NavigationField edges are fog-aware; force a redraw so newly hidden edges
	# drop out of the field of view without waiting for the next frame.
	if is_instance_valid(_navigation):
		_navigation.queue_redraw()
	queue_redraw()


func _is_frontier_for_player(planet: Node2D) -> bool:
	for neighbor in get_neighbors(planet):
		var neighbor_planet: Planet = neighbor as Planet
		if neighbor_planet != null and neighbor_planet.get_faction() == GameState.FACTION_PLAYER:
			return true
	return false


# --- Camera / drag / ship wiring (Signal-Verdrahtung bleibt im Network) ---


func _connect_map_camera() -> void:
	if _map_camera != null and is_instance_valid(_map_camera) and not _map_camera.planet_drag_dropped.is_connected(_on_planet_drag_dropped):
		_map_camera.planet_drag_dropped.connect(_on_planet_drag_dropped)


func _connect_conflict_ships() -> void:
	var conflict_manager: Node = get_parent().get_node_or_null("ConflictManager")
	if conflict_manager == null:
		return
	if conflict_manager.has_signal("ship_dispatched") and not conflict_manager.is_connected("ship_dispatched", _on_ship_dispatched):
		conflict_manager.connect("ship_dispatched", _on_ship_dispatched)
	if conflict_manager.has_signal("ship_arrived") and not conflict_manager.is_connected("ship_arrived", _on_ship_arrived):
		conflict_manager.connect("ship_arrived", _on_ship_arrived)
	# Connect existing materialized ships (e.g. restore from save).
	if conflict_manager.has_method("get_active_ships"):
		for ship in conflict_manager.get_active_ships() as Array[ShipBase]:
			_connect_ship_selection(ship)


func _connect_ship_selection(ship: ShipBase) -> void:
	if _world_ui != null:
		_world_ui.connect_ship_selection(ship)


func _on_ship_dispatched(ship: ShipBase) -> void:
	if _world_ui != null:
		_world_ui.on_ship_dispatched(ship)


func _on_ship_arrived(_ship: Node2D) -> void:
	if _world_ui != null:
		_world_ui.on_ship_arrived()


func _on_planet_drag_dropped(source: Node2D, destination: Node2D) -> void:
	if not is_instance_valid(_ui) or source == null or destination == null or source == destination:
		return
	if _selection_service != null:
		_selection_service.handle_request(source, {})
	else:
		_on_planet_selected(source)
	var destination_index := _ui.index_of_destination(destination.name)
	if destination_index >= 0:
		_on_destination_selected(destination_index)


func _on_workers_spawn_requested(source: Node2D, amount: int) -> void:
	_worker_manager.call("_spawn_clusters", source, amount)


func _on_panel_visibility_changed(_panel_open: bool) -> void:
	queue_redraw()