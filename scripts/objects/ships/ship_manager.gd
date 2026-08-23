class_name ShipManager
extends Node2D

const SHIP_BASE_SCENE: PackedScene = preload("res://scenes/objects/ships/ship_base.tscn")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")
const DEFAULT_TECH_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"

@export var ship_config: ShipConfig = DEFAULT_SHIP_CONFIG
@export var technology_catalog: TechnologyCatalog = DEFAULT_TECH_CATALOG
@export var ship_part_catalog: ShipPartCatalog = DEFAULT_SHIP_PART_CATALOG

var _field: Node
var _network: Node
var _enabled := true

func _ready() -> void:
	var state: Node = _game_state()
	if state == null:
		return
	if state.has_signal("ship_assembled") and not state.ship_assembled.is_connected(_on_ship_assembled):
		state.ship_assembled.connect(_on_ship_assembled)

func _on_ship_assembled(planet_id: StringName, _ship_id: StringName) -> void:
	for planet in get_planets():
		if planet.planet_id == planet_id:
			refresh_ship_display(planet)
			return

func configure(field: Node, _navigation: Node, config: ShipConfig = null, catalog: TechnologyCatalog = null, network: Node = null) -> void:
	_field = field
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

func can_launch_research_ship(source: Planet) -> bool:
	if not _enabled or source == null or source.get_faction() == GameState.FACTION_NEUTRAL:
		return false
	var state: Node = _game_state()
	if state == null or not state.has_method("get_research_ship_records"):
		return false
	for data in state.get_research_ship_records(source.get_faction()):
		if data.get("status", &"") == &"idle" and data.get("current_planet_id", &"") == source.planet_id:
			return true
	return false

func launch_research_ship(source: Planet, destination: Planet) -> ShipBase:
	if not can_launch_research_ship(source) or destination == null or destination == source:
		return null
	if not get_scan_destinations(source).has(destination):
		return null
	var conflict_manager: Node = _field.get_node_or_null("ConflictManager") if _field != null else null
	if conflict_manager == null or not conflict_manager.has_method("dispatch_research_ship"):
		return null
	return conflict_manager.call("dispatch_research_ship", source, destination) as ShipBase

func get_research_ship_status() -> Array[Dictionary]:
	var state: Node = _game_state()
	return state.get_research_ship_records(GameState.FACTION_PLAYER) if state != null and state.has_method("get_research_ship_records") else []

func dispatch_ship(source: Planet, destination: Planet, ship_id: StringName, role: StringName = &"") -> ShipBase:
	if not _enabled or source == null or destination == null or destination == source:
		return null
	var conflict_manager: Node = _field.get_node_or_null("ConflictManager") if _field != null else null
	if conflict_manager == null or not conflict_manager.has_method("dispatch_ship"):
		return null
	return conflict_manager.call("dispatch_ship", source, destination, ship_id, role) as ShipBase

func get_ship_destinations(source: Planet, role: StringName = &"military") -> Array[Planet]:
	var result: Array[Planet] = []
	if source == null or _network == null or not is_instance_valid(_network):
		return result
	var state: Node = _game_state()
	if state == null or not _network.has_method("get_route_destinations"):
		return result
	for candidate in _network.get_route_destinations(source):
		var planet: Planet = candidate as Planet
		if planet == null or planet == source:
			continue
		if role == &"colony":
			if planet.get_faction() == GameState.FACTION_NEUTRAL and state.has_scanned_planet(source.get_faction(), planet.planet_id):
				result.append(planet)
		elif planet.get_faction() != source.get_faction():
			result.append(planet)
	return result

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
		if planet != null and planet.get_faction() == GameState.FACTION_NEUTRAL and not state.is_known(planet.planet_id, source.get_faction()):
			result.append(planet)
	return result

func can_build_workers(source: Planet) -> bool:
	if not _enabled or source == null:
		return false
	var config := get_ship_config()
	var state: Node = _game_state()
	return state != null and state.get_available_workers(source.planet_id, source.worker_count) > 0 and state.can_build_worker_factory(source.planet_id, config.worker_build_cost_resource, config.worker_build_cost_amount, config.worker_build_credit_cost)

func build_workers(source: Planet) -> bool:
	if not can_build_workers(source):
		return false
	var config := get_ship_config()
	var state: Node = _game_state()
	var job_id := StringName("worker_factory_%s" % String(source.planet_id))
	if not state.reserve_workers(source.planet_id, job_id, 1, source.worker_count):
		return false
	var built: bool = state.build_worker_factory(source.planet_id, config.worker_build_cost_resource, config.worker_build_cost_amount, config.worker_build_credit_cost)
	state.release_workers(source.planet_id, job_id)
	return built

func can_buy_part(source: Planet, part_id: StringName) -> bool:
	var state: Node = _game_state()
	return _enabled and source != null and state != null and state.can_buy_ship_part(source.planet_id, part_id, get_part_catalog())

func buy_part(source: Planet, part_id: StringName) -> bool:
	var state: Node = _game_state()
	if not _enabled or source == null or state == null:
		return false
	return state.buy_ship_part(source.planet_id, part_id, get_part_catalog())

func can_assemble_ship(source: Planet, hull_id: StringName, scanner_id: StringName, module_ids: Array, weapon_id: StringName, drive_id: StringName, shield_id: StringName) -> bool:
	var state: Node = _game_state()
	if not _enabled or source == null or state == null:
		return false
	if not state.has_planet_upgrade(source.planet_id, SHIPYARD_UPGRADE_ID):
		return false
	var occupied_slots: int = state.get_ship_build_jobs(source.planet_id).size() + state.get_ship_assemblies(source.planet_id).size()
	if occupied_slots >= source.get_build_slot_count():
		return false
	if not state.can_spend_faction_credits(source.get_faction(), get_ship_config().ship_assembly_credit_cost):
		return false
	return state.get_available_workers(source.planet_id, source.worker_count) > 0 and state.can_assemble_ship(source.planet_id, hull_id, scanner_id, module_ids, get_part_catalog(), weapon_id, drive_id, shield_id)

func assemble_ship(source: Planet, hull_id: StringName, scanner_id: StringName, module_ids: Array, weapon_id: StringName, drive_id: StringName, shield_id: StringName, blueprint_id: StringName = &"", instance_seed: int = -1, ship_role: StringName = &"") -> StringName:
	var state: Node = _game_state()
	if not can_assemble_ship(source, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id):
		return &""
	var ship_domain: ShipDomain = state.get("ship_domain") as ShipDomain
	var predicted_ship_id: StringName = StringName("ship_%d" % (ship_domain.next_ship_index + 1)) if ship_domain != null else &""
	if not state.reserve_workers(source.planet_id, predicted_ship_id, 1, source.worker_count):
		return &""
	if not state.spend_faction_credits(source.get_faction(), get_ship_config().ship_assembly_credit_cost):
		state.release_workers(source.planet_id, predicted_ship_id)
		return &""
	var ship_id: StringName = state.assemble_ship(source.planet_id, hull_id, scanner_id, module_ids, get_part_catalog(), weapon_id, drive_id, shield_id, blueprint_id, instance_seed, ship_role) as StringName
	if not String(ship_id).is_empty():
		refresh_ship_display(source)
	else:
		state.add_faction_credits(source.get_faction(), get_ship_config().ship_assembly_credit_cost)
		state.release_workers(source.planet_id, predicted_ship_id)
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
	var assembly: ShipAssembly = null
	if assemblies.is_empty():
		var build_jobs: Dictionary = state.get_ship_build_jobs(source.planet_id)
		if build_jobs.is_empty():
			hangar.hide_ship()
			return
		assembly = build_jobs[build_jobs.keys()[0]] as ShipAssembly
	else:
		assembly = assemblies[assemblies.keys()[0]] as ShipAssembly
	if assembly == null:
		hangar.hide_ship()
		return
	var cat := get_part_catalog()
	var hull := cat.resolve(assembly.hull_id)
	var scanner := cat.resolve(assembly.scanner_id)
	var drive := cat.resolve(assembly.drive_id)
	var weapon := cat.resolve(assembly.weapon_id)
	var shield := cat.resolve(assembly.shield_id)
	var module_parts: Array[ShipPartDefinition] = []
	for module_id in assembly.module_ids:
		var module := cat.resolve(module_id)
		if module != null:
			module_parts.append(module)
	var view_variants: Dictionary = {}
	for slot_type in [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]:
		var part_id: StringName = assembly.hull_id
		match slot_type:
			ShipPartDefinition.SLOT_DRIVE:
				part_id = assembly.drive_id
			ShipPartDefinition.SLOT_WEAPON:
				part_id = assembly.weapon_id
			ShipPartDefinition.SLOT_SHIELD:
				part_id = assembly.shield_id
			ShipPartDefinition.SLOT_SCANNER:
				part_id = assembly.scanner_id
		var part: ShipPartDefinition = cat.resolve(part_id)
		var variant: ShipComponentVariant = cat.resolve_variant(part, assembly.variant_id_for(slot_type))
		if variant != null:
			view_variants[slot_type] = variant
	var utility_variants: Array[ShipComponentVariant] = []
	for index in range(module_parts.size()):
		var utility_variant: ShipComponentVariant = cat.resolve_variant(module_parts[index], assembly.variant_id_for(ShipPartDefinition.SLOT_UTILITY, index))
		utility_variants.append(utility_variant)
	view_variants[ShipPartDefinition.SLOT_UTILITY] = utility_variants
	hangar.show_ship_parts(hull, scanner, drive, weapon, shield, module_parts, source.get_faction(), view_variants)
	var role: String = String(assembly.role).to_upper()
	var summary: String = "%s · %s" % [role, hull.display_name if hull != null else "SHIP"]
	hangar.set_build_readback(summary, _ship_readback_tooltip(cat, assembly), 0.0)

func _ship_readback_tooltip(catalog: ShipPartCatalog, assembly: ShipAssembly) -> String:
	var fleet := FleetSnapshot.new()
	fleet.faction = GameState.FACTION_PLAYER
	fleet.ships = [assembly.copy()]
	fleet.calculate_stats(catalog)
	var lines: Array[String] = ["Rolle: %s" % String(assembly.role).to_upper()]
	var slot_types: Array[StringName] = [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]
	for slot_type in slot_types:
		var part_id: StringName = assembly.hull_id
		match slot_type:
			ShipPartDefinition.SLOT_DRIVE:
				part_id = assembly.drive_id
			ShipPartDefinition.SLOT_WEAPON:
				part_id = assembly.weapon_id
			ShipPartDefinition.SLOT_SHIELD:
				part_id = assembly.shield_id
			ShipPartDefinition.SLOT_SCANNER:
				part_id = assembly.scanner_id
		var part: ShipPartDefinition = catalog.resolve(part_id)
		if part == null:
			continue
		var variant: ShipComponentVariant = catalog.resolve_variant(part, assembly.variant_id_for(slot_type))
		lines.append("%s: %s%s" % [String(slot_type).capitalize(), part.display_name, " / " + variant.display_name if variant != null else ""])
	lines.append("Stats: HP %.0f · DPS %.1f · Range %.0f · Speed x%.2f" % [fleet.total_hull_hp, fleet.total_dps, fleet.effective_range, fleet.transfer_speed_multiplier()])
	return "\\n".join(lines)

func get_planets() -> Array[Planet]:
	if _field == null or not is_instance_valid(_field):
		return []
	var result: Array[Planet] = []
	for child in _field.get_children():
		if child is Planet:
			result.append(child)
	return result

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
