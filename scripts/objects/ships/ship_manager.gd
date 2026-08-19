class_name ShipManager
extends Node2D

const SCOUT_SCENE: PackedScene = preload("res://scenes/objects/ships/scout_ship.tscn")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")
const DEFAULT_TECH_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"
const DEFAULT_HULL_TEXTURE: Texture2D = preload("res://assets/objects/workers/cluster_k.svg")
const DEFAULT_SCANNER_TEXTURE: Texture2D = preload("res://assets/objects/satellites/planet_satellite.svg")

@export var ship_config: ShipConfig = DEFAULT_SHIP_CONFIG
@export var technology_catalog: TechnologyCatalog = DEFAULT_TECH_CATALOG
@export var ship_part_catalog: ShipPartCatalog = DEFAULT_SHIP_PART_CATALOG

var _field: Node
var _navigation: NavigationField
var _network: Node
var _enabled := true
var _scouts: Array[Node2D] = []
var _active_build_counts: Dictionary = {}

func _ready() -> void:
	var state: Node = _game_state()
	if state != null and state.has_signal("catalog_reset") and not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	_active_build_counts.clear()
	for scout in _scouts:
		if is_instance_valid(scout):
			scout.queue_free()
	_scouts.clear()

func configure(field: Node, navigation: Node, config: ShipConfig = null, catalog: TechnologyCatalog = null, network: Node = null) -> void:
	_field = field
	_navigation = navigation as NavigationField
	_network = network if network != null else field.get_node_or_null("PlanetNetwork")
	ship_config = config if config != null else DEFAULT_SHIP_CONFIG
	technology_catalog = catalog if catalog != null else DEFAULT_TECH_CATALOG

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func is_enabled() -> bool:
	return _enabled

func get_ship_config() -> ShipConfig:
	return ship_config if ship_config != null else DEFAULT_SHIP_CONFIG

func get_technology_catalog() -> TechnologyCatalog:
	return technology_catalog if technology_catalog != null else DEFAULT_TECH_CATALOG

func get_part_catalog() -> ShipPartCatalog:
	return ship_part_catalog if ship_part_catalog != null else DEFAULT_SHIP_PART_CATALOG

func can_build_scout(source: Planet) -> bool:
	if not _enabled or source == null:
		return false
	var state: Node = _game_state()
	if state == null:
		return false
	var faction: StringName = source.get_faction()
	if faction == GameState.FACTION_NEUTRAL:
		return false
	if not state.has_planet_upgrade(source.planet_id, SHIPYARD_UPGRADE_ID):
		return false
	var config := get_ship_config()
	if not state.has_technology(faction, config.scout_hull_tech_id):
		return false
	if not state.has_technology(faction, config.scout_scanner_tech_id):
		return false
	if state.get_faction_resource(faction, config.scout_build_cost_resource) < config.scout_build_cost_amount:
		return false
	if get_active_build_count(source) >= source.get_build_slot_count():
		return false
	return true

func build_scout(source: Planet, destination: Planet) -> ScoutShip:
	if not can_build_scout(source) or destination == null or destination == source:
		return null
	var state: Node = _game_state()
	var faction: StringName = source.get_faction()
	if state == null or not get_scan_destinations(source).has(destination):
		return null
	var config := get_ship_config()
	if not state.spend_faction_resource(faction, config.scout_build_cost_resource, config.scout_build_cost_amount):
		return null
	var route_path := _route(source, destination)
	var duration := _flight_duration(route_path)
	var scout: ScoutShip = SCOUT_SCENE.instantiate()
	scout.name = "Scout_%s_%s" % [source.name, destination.name]
	add_child(scout)
	scout.configure(destination, faction, route_path, duration, _hull_texture(), _scanner_texture(), source.planet_id, config)
	scout.arrived.connect(_on_scout_arrived)
	_active_build_counts[source.planet_id] = get_active_build_count(source) + 1
	_scouts.append(scout)
	scout.start_flight()
	return scout

func dispatch_once(source: Planet, destination: Planet) -> ScoutShip:
	return build_scout(source, destination)

func _on_scout_arrived(scout: Node2D) -> void:
	_scouts.erase(scout)
	var source_planet_id: StringName = scout.get("source_planet_id") as StringName
	if not String(source_planet_id).is_empty():
		_active_build_counts[source_planet_id] = maxi(get_active_build_count_by_id(source_planet_id) - 1, 0)
		if int(_active_build_counts[source_planet_id]) == 0:
			_active_build_counts.erase(source_planet_id)
	if is_instance_valid(scout):
		scout.queue_free()

func get_scan_destinations(source: Planet) -> Array[Planet]:
	var result: Array[Planet] = []
	if source == null:
		return result
	var state: Node = _game_state()
	if state == null:
		return result
	var candidates: Array[Node2D] = []
	if _network != null and is_instance_valid(_network) and _network.has_method("get_neighbors"):
		candidates = _network.get_neighbors(source)
	for candidate in candidates:
		var planet: Planet = candidate as Planet
		if planet != null and not state.is_known(planet.planet_id, source.get_faction()):
			result.append(planet)
	return result

func can_build_workers(source: Planet) -> bool:
	if not _enabled or source == null:
		return false
	var config := get_ship_config()
	var state: Node = _game_state()
	return state != null and state.can_build_worker_factory(source.planet_id, config.worker_build_cost_resource, config.worker_build_cost_amount)

func build_workers(source: Planet) -> bool:
	if not can_build_workers(source):
		return false
	var config := get_ship_config()
	var state: Node = _game_state()
	return state.build_worker_factory(source.planet_id, config.worker_build_cost_resource, config.worker_build_cost_amount)

func can_buy_part(source: Planet, part_id: StringName) -> bool:
	var state: Node = _game_state()
	return _enabled and source != null and state != null and state.can_buy_ship_part(source.planet_id, part_id, get_part_catalog())

func buy_part(source: Planet, part_id: StringName) -> bool:
	var state: Node = _game_state()
	if not _enabled or source == null or state == null:
		return false
	return state.buy_ship_part(source.planet_id, part_id, get_part_catalog())

func can_assemble_ship(source: Planet, hull_id: StringName, scanner_id: StringName, module_ids: Array) -> bool:
	var state: Node = _game_state()
	return _enabled and source != null and state != null and state.can_assemble_ship(source.planet_id, hull_id, scanner_id, module_ids, get_part_catalog())

func assemble_ship(source: Planet, hull_id: StringName, scanner_id: StringName, module_ids: Array) -> StringName:
	var state: Node = _game_state()
	if not _enabled or source == null or state == null:
		return &""
	var ship_id: StringName = state.assemble_ship(source.planet_id, hull_id, scanner_id, module_ids, get_part_catalog()) as StringName
	if not String(ship_id).is_empty():
		refresh_ship_display(source)
	return ship_id

func can_disassemble_ship(source: Planet, ship_id: StringName) -> bool:
	var state: Node = _game_state()
	return _enabled and source != null and state != null and state.has_ship_assembly(source.planet_id, ship_id)

func disassemble_ship(source: Planet, ship_id: StringName) -> bool:
	var state: Node = _game_state()
	if not _enabled or source == null or state == null:
		return false
	var removed: bool = state.disassemble_ship(source.planet_id, ship_id)
	if removed:
		refresh_ship_display(source)
	return removed

func refresh_ship_display(source: Planet) -> void:
	if source == null:
		return
	var hangar: ShipyardHangar = source.get_node_or_null("PlanetDetails/UpgradeStructure_shipyard/Hangar") as ShipyardHangar
	if hangar == null:
		return
	var state: Node = _game_state()
	if state == null:
		return
	var assemblies: Dictionary = state.get_ship_assemblies(source.planet_id)
	if assemblies.is_empty():
		hangar.hide_ship()
		return
	var ship_id: StringName = (assemblies.keys()[0]) as StringName
	var assembly: Dictionary = assemblies[ship_id]
	var cat := get_part_catalog()
	var hull := cat.resolve(assembly.get("hull", &"") as StringName)
	var scanner := cat.resolve(assembly.get("scanner", &"") as StringName)
	var module_textures: Array[Texture2D] = []
	for module_value in assembly.get("modules", []):
		var module := cat.resolve(module_value as StringName)
		if module != null:
			module_textures.append(module.visual_asset)
	hangar.show_ship(
		hull.visual_asset if hull != null else null,
		scanner.visual_asset if scanner != null else null,
		module_textures
	)

func get_active_build_count(source: Planet) -> int:
	return get_active_build_count_by_id(source.planet_id) if source != null else 0

func get_active_build_count_by_id(planet_id: StringName) -> int:
	return int(_active_build_counts.get(planet_id, 0))

func get_planets() -> Array[Planet]:
	if _field == null or not is_instance_valid(_field):
		return []
	var result: Array[Planet] = []
	for child in _field.get_children():
		if child is Planet:
			result.append(child)
	return result

func scout_count() -> int:
	var alive: Array[Node2D] = []
	for scout in _scouts:
		if is_instance_valid(scout):
			alive.append(scout)
	_scouts = alive
	return _scouts.size()

func _route(source: Planet, destination: Planet) -> Array[Vector2]:
	if _navigation != null and is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]

func _flight_duration(route_path: Array[Vector2]) -> float:
	var distance := 0.0
	for index in range(route_path.size() - 1):
		distance += route_path[index].distance_to(route_path[index + 1])
	var config := get_ship_config()
	return distance / maxf(config.scout_speed, 1.0)

func _hull_texture() -> Texture2D:
	return _tech_asset(get_ship_config().scout_hull_tech_id, DEFAULT_HULL_TEXTURE)

func _scanner_texture() -> Texture2D:
	return _tech_asset(get_ship_config().scout_scanner_tech_id, DEFAULT_SCANNER_TEXTURE)

func _tech_asset(tech_id: StringName, fallback: Texture2D) -> Texture2D:
	var catalog := get_technology_catalog()
	var technology := catalog.resolve(tech_id)
	if technology != null and technology.visual_asset != null:
		return technology.visual_asset
	return fallback

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
