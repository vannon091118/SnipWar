class_name ShipManager
extends Node2D

const SCOUT_SCENE: PackedScene = preload("res://scenes/objects/ships/scout_ship.tscn")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")
const DEFAULT_TECH_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"
const DEFAULT_HULL_TEXTURE: Texture2D = preload("res://assets/objects/workers/cluster_k.svg")
const DEFAULT_SCANNER_TEXTURE: Texture2D = preload("res://assets/objects/planets/planet_satellite.svg")

@export var ship_config: ShipConfig = DEFAULT_SHIP_CONFIG
@export var technology_catalog: TechnologyCatalog = DEFAULT_TECH_CATALOG

var _field: Node
var _navigation: NavigationField
var _enabled := true
var _scouts: Array[Node2D] = []

func configure(field: Node, navigation: Node, config: ShipConfig = null, catalog: TechnologyCatalog = null) -> void:
	_field = field
	_navigation = navigation as NavigationField
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
	return true

func build_scout(source: Planet, destination: Planet) -> ScoutShip:
	if not can_build_scout(source) or destination == null or destination == source:
		return null
	var state: Node = _game_state()
	var faction: StringName = source.get_faction()
	if state == null or state.is_known(destination.planet_id, faction):
		return null
	var config := get_ship_config()
	if not state.spend_faction_resource(faction, config.scout_build_cost_resource, config.scout_build_cost_amount):
		return null
	var route_path := _route(source, destination)
	var duration := _flight_duration(route_path)
	var scout: ScoutShip = SCOUT_SCENE.instantiate()
	scout.name = "Scout_%s_%s" % [source.name, destination.name]
	add_child(scout)
	scout.configure(destination, faction, route_path, duration, _hull_texture(), _scanner_texture())
	scout.arrived.connect(_on_scout_arrived)
	_scouts.append(scout)
	scout.start_flight()
	return scout

func dispatch_once(source: Planet, destination: Planet) -> ScoutShip:
	return build_scout(source, destination)

func _on_scout_arrived(scout: Node2D) -> void:
	_scouts.erase(scout)
	if is_instance_valid(scout):
		scout.queue_free()

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
