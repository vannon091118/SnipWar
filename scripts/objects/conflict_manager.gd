extends Node

const SHIP_BASE_SCENE: PackedScene = preload("res://scenes/objects/ships/ship_base.tscn")
const DEFAULT_TRANSIT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const FLIGHT_TIME_SCRIPT: Script = preload("res://scripts/flight_time.gd")

var transit_config: TransitConfig = DEFAULT_TRANSIT_CONFIG
var _field: Node
var _navigation: NavigationField
var _ship_manager: Node
var _enabled: bool = true
var _active_ships: Array[ShipBase] = []

func _ready() -> void:
	var state: Node = _game_state()
	if state != null and state.has_signal("catalog_reset") and not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)

func configure(field: Node, navigation: Node, ship_manager: Node, config: TransitConfig = null) -> void:
	_field = field
	_navigation = navigation as NavigationField
	_ship_manager = ship_manager
	transit_config = config if config != null else DEFAULT_TRANSIT_CONFIG

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func active_ship_count() -> int:
	_prune_active_ships()
	return _active_ships.size()

func dispatch_ship(source: Planet, destination: Planet, ship_id: StringName, role: StringName = &"") -> ShipBase:
	if not _enabled or source == null or destination == null or source == destination:
		return null
	var state: Node = _game_state()
	if state == null or not state.has_ship_assembly(source.planet_id, ship_id):
		return null
	var assembly: Dictionary = state.get_ship_assembly(source.planet_id, ship_id)
	var resolved_role: StringName = role
	if String(resolved_role).is_empty():
		resolved_role = assembly.get("role", &"colony") as StringName
	if resolved_role == GameState.MISSION_COLONY:
		resolved_role = &"colony"
	if resolved_role == &"colony":
		if destination.get_faction() != GameState.FACTION_NEUTRAL or not state.has_scanned_planet(source.get_faction(), destination.planet_id):
			return null
	var route_path: Array[Vector2] = _route(source, destination)
	if route_path.size() < 2:
		return null
	var fleet: FleetSnapshot = state.create_fleet_from_planet(source.planet_id, [ship_id], _part_catalog())
	if fleet == null or fleet.ships.is_empty():
		return null
	fleet.destination_planet_id = destination.planet_id
	fleet.mission_role = resolved_role
	var distance: float = PathUtils.distance(route_path)
	var duration: float = FLIGHT_TIME_SCRIPT.seconds_for_ship(distance, fleet.ships.size(), transit_config, fleet.transfer_speed_multiplier())
	var ship: ShipBase = SHIP_BASE_SCENE.instantiate() as ShipBase
	ship.name = "Ship_%s_%s" % [source.name, destination.name]
	ship.configure(fleet, destination, route_path, duration, _part_catalog(), resolved_role, source.planet_id)
	add_child(ship)
	ship.arrived.connect(_on_ship_arrived)
	_active_ships.append(ship)
	state.ship_launched.emit(source.planet_id, ship_id, resolved_role)
	ship.start_flight()
	return ship

func preview_duration(source: Planet, destination: Planet, ship_id: StringName) -> float:
	var state: Node = _game_state()
	if state == null or source == null or destination == null:
		return 0.0
	var assembly: Dictionary = state.get_ship_assembly(source.planet_id, ship_id)
	if assembly.is_empty():
		return 0.0
	var route_path: Array[Vector2] = _route(source, destination)
	var fleet := _fleet_preview(source, assembly)
	if fleet == null:
		return 0.0
	return FLIGHT_TIME_SCRIPT.seconds_for_ship(PathUtils.distance(route_path), fleet.ships.size(), transit_config, fleet.transfer_speed_multiplier())

func _on_ship_arrived(ship_node: Node2D) -> void:
	var ship: ShipBase = ship_node as ShipBase
	if ship == null:
		return
	var state: Node = _game_state()
	var result: Dictionary = {}
	if ship.destination != null and is_instance_valid(ship.destination) and ship.fleet != null:
		var defender_fleet: FleetSnapshot = _defender_fleet(ship.destination, ship.fleet.faction, ship.mission_role)
		result = ship.destination.resolve_ship_arrival(ship.fleet, defender_fleet, 1337, 42, ship.mission_role)
		ship.destination.show_arrival_feedback(int(result.get("surviving_attackers", 0)), ship.fleet.faction)
	var ship_id: StringName = &""
	if ship.fleet != null and not ship.fleet.ships.is_empty():
		ship_id = ship.fleet.ships[0].get("id", &"") as StringName
	var outcome: StringName = result.get("result", Planet.ARRIVAL_REJECTED) as StringName
	if state != null:
		if outcome == Planet.ARRIVAL_SETTLED and ship.mission_role == &"colony":
			state.mark_milestone(ship.fleet.faction, &"first_colony")
		elif outcome == Planet.ARRIVAL_FRIENDLY and ship.destination != null and is_instance_valid(ship.destination):
			state.disband_fleet_to_planet(ship.fleet, ship.destination.planet_id)
		elif outcome == Planet.ARRIVAL_REPELLED or outcome == Planet.ARRIVAL_REJECTED:
			state.ship_lost.emit(ship.source_planet_id, ship_id)
	_active_ships.erase(ship)
	if is_instance_valid(ship):
		ship.queue_free()

func _defender_fleet(destination: Planet, attacking_faction: StringName, mission_role: StringName) -> FleetSnapshot:
	if destination == null or mission_role == &"colony" or destination.get_faction() == attacking_faction:
		return null
	var state: Node = _game_state()
	if state == null or not state.has_method("preview_fleet_from_planet"):
		return null
	var assemblies: Dictionary = state.get_ship_assemblies(destination.planet_id)
	if assemblies.is_empty():
		return null
	return state.preview_fleet_from_planet(destination.planet_id, assemblies.keys(), _part_catalog())

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	for ship in _active_ships:
		if is_instance_valid(ship):
			ship.queue_free()
	_active_ships.clear()

func _route(source: Planet, destination: Planet) -> Array[Vector2]:
	if _navigation != null and is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]

func _fleet_preview(source: Planet, assembly: Dictionary) -> FleetSnapshot:
	var fleet := FleetSnapshot.new()
	fleet.faction = source.get_faction()
	fleet.source_planet_id = source.planet_id
	fleet.ships = [assembly.duplicate(true)]
	fleet.calculate_stats(_part_catalog())
	return fleet

func _part_catalog() -> ShipPartCatalog:
	if _ship_manager != null and _ship_manager.has_method("get_part_catalog"):
		return _ship_manager.get_part_catalog()
	return preload("res://resources/config/ship_part_catalog_default.tres")

func _prune_active_ships() -> void:
	var alive: Array[ShipBase] = []
	for ship in _active_ships:
		if is_instance_valid(ship):
			alive.append(ship)
	_active_ships = alive

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
