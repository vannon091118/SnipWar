extends Node

## Centralized GameState Facade for SnipWar.
## Composes modular domain managers (FactionDomain, EconomyDomain, TechDomain, ShipDomain)
## while maintaining full backward compatibility for public API, signals, and preflight tests.

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"

const MISSION_MILITARY := &"military"
const MISSION_CARGO := &"cargo"
const MISSION_COLONY := &"colony"
const MISSION_COLLECT := &"collect"
const TECH_WORKER_AUTOMATION := &"worker_automation"

const RES_ENERGY: StringName = &"energy"
const RES_BIOMASS: StringName = &"biomass"
const RES_RARE: StringName = &"rare"
const RES_MATERIAL: StringName = &"material"
const RES_VOLATILE: StringName = &"volatile"

const ALL_RESOURCES: Array[StringName] = [
	RES_ENERGY,
	RES_BIOMASS,
	RES_RARE,
	RES_MATERIAL,
	RES_VOLATILE,
]

static func is_valid_resource(resource_id: StringName) -> bool:
	return resource_id == RES_ENERGY or resource_id == RES_BIOMASS or resource_id == RES_RARE or resource_id == RES_MATERIAL or resource_id == RES_VOLATILE

const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)
signal catalog_reset(catalog: PlanetCatalog)
signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal planet_upgraded(planet_id: StringName, upgrade_id: StringName)
signal resource_generated(planet_id: StringName, resource_id: StringName, amount: int)
signal planet_discovered(faction: StringName, planet_id: StringName)
signal planet_scanned(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int)
signal technology_researched(faction: StringName, technology_id: StringName)
signal planet_technology_researched(planet_id: StringName, technology_id: StringName)
signal resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int)
signal gathering_started(faction: StringName, planet_id: StringName, workers: int)
signal gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int)
signal worker_factory_built(planet_id: StringName)
signal ship_part_purchased(planet_id: StringName, part_id: StringName)
signal ship_assembled(planet_id: StringName, ship_id: StringName)
signal ship_disassembled(planet_id: StringName, ship_id: StringName)
signal ship_launched(planet_id: StringName, ship_id: StringName, role: StringName)
signal ship_lost(planet_id: StringName, ship_id: StringName)
signal milestone_reached(faction: StringName, milestone_id: StringName)
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
signal research_started(faction: StringName, technology_id: StringName, remaining: float)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)

var faction_domain := FactionDomain.new()
var economy_domain := EconomyDomain.new()
var tech_domain := TechDomain.new()
var ship_domain := ShipDomain.new()

# Compatibility views retained while the state implementation is split into
# domains. Older UI/preflight callers inspect these dictionaries through Node.get().
@warning_ignore("unused_private_class_variable")
var _ownership: Dictionary:
	get:
		return faction_domain.ownership
@warning_ignore("unused_private_class_variable")
var _starting_workers: Dictionary:
	get:
		return faction_domain.starting_workers
@warning_ignore("unused_private_class_variable")
var _homeworlds: Dictionary:
	get:
		return faction_domain.homeworlds
@warning_ignore("unused_private_class_variable")
var _known_planets: Dictionary:
	get:
		return faction_domain.known_planets
@warning_ignore("unused_private_class_variable")
var _faction_vaults: Dictionary:
	get:
		return economy_domain.faction_vaults
@warning_ignore("unused_private_class_variable")
var _planet_resources: Dictionary:
	get:
		return economy_domain.planet_resources
@warning_ignore("unused_private_class_variable")
var _planet_upgrades: Dictionary:
	get:
		return economy_domain.planet_upgrades
@warning_ignore("unused_private_class_variable")
var _gathering_workers: Dictionary:
	get:
		return economy_domain.gathering_workers
@warning_ignore("unused_private_class_variable")
var _ship_part_inventory: Dictionary:
	get:
		return ship_domain.ship_part_inventory

var _jobs_auto_advance: bool = true

func _init() -> void:
	_connect_domain_signals()
	economy_domain.reset_vaults()

func _connect_domain_signals() -> void:
	# Typed signals in Godot 4.x must be forwarded with explicit arg lists, so
	# each connection lists the source/domain and target/facade pair.
	faction_domain.faction_changed.connect(func(p, o, n): faction_changed.emit(p, o, n))
	faction_domain.planet_discovered.connect(func(f, p): planet_discovered.emit(f, p))
	faction_domain.planet_scanned.connect(func(f, p, r, s, b): planet_scanned.emit(f, p, r, s, b))
	faction_domain.milestone_reached.connect(func(f, m): milestone_reached.emit(f, m))

	economy_domain.faction_resources_changed.connect(func(f, r, a): faction_resources_changed.emit(f, r, a))
	economy_domain.planet_upgraded.connect(func(p, u): planet_upgraded.emit(p, u))
	economy_domain.resource_generated.connect(func(p, r, a): resource_generated.emit(p, r, a))
	economy_domain.resources_collected.connect(func(f, p, r, a): resources_collected.emit(f, p, r, a))
	economy_domain.gathering_started.connect(func(f, p, w): gathering_started.emit(f, p, w))
	economy_domain.gathering_withdrawn.connect(func(f, p, w): gathering_withdrawn.emit(f, p, w))
	economy_domain.worker_factory_built.connect(func(p): worker_factory_built.emit(p))
	economy_domain.refinery_converted.connect(func(p, f, c, pr): refinery_converted.emit(p, f, c, pr))

	tech_domain.technology_researched.connect(func(f, t): technology_researched.emit(f, t))
	tech_domain.planet_technology_researched.connect(func(p, t): planet_technology_researched.emit(p, t))
	tech_domain.research_started.connect(func(f, t, r): research_started.emit(f, t, r))

	ship_domain.ship_part_purchased.connect(func(p, pt): ship_part_purchased.emit(p, pt))
	ship_domain.ship_assembled.connect(func(p, s): ship_assembled.emit(p, s))
	ship_domain.ship_disassembled.connect(func(p, s): ship_disassembled.emit(p, s))
	ship_domain.ship_launched.connect(func(p, s, r): ship_launched.emit(p, s, r))
	ship_domain.ship_lost.connect(func(p, s): ship_lost.emit(p, s))
	ship_domain.ship_build_started.connect(func(p, s, r): ship_build_started.emit(p, s, r))

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	faction_domain.reset(catalog)
	economy_domain.reset()
	tech_domain.reset()
	ship_domain.reset()
	catalog_reset.emit(catalog)

func set_jobs_auto_advance(auto_advance: bool) -> void:
	_jobs_auto_advance = auto_advance

func advance_research(delta: float) -> void:
	tech_domain.advance_research(delta)

func advance_builds(delta: float) -> void:
	ship_domain.advance_builds(delta)

func _process(delta: float) -> void:
	if _jobs_auto_advance:
		advance_research(delta)
		advance_builds(delta)

# --- FACTION & OWNERSHIP DELEGATES ---
func set_faction(planet_id: StringName, faction: StringName) -> void:
	faction_domain.set_faction(planet_id, faction)

func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	faction_domain.register_planet(planet_id, initial_faction)

func seed_starting_workers(planet_id: StringName, profile: PlanetSizeProfile) -> void:
	faction_domain.seed_starting_workers(planet_id, profile)

func faction_of(planet_id: StringName) -> StringName:
	return faction_domain.faction_of(planet_id)

func is_owned_by(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_owned_by(planet_id, faction)

# Kept under the old name for callers that didn't migrate to is_owned_by.
func owns(planet_id: StringName, faction: StringName) -> bool:
	return is_owned_by(planet_id, faction)

func homeworld_for(faction: StringName) -> StringName:
	return faction_domain.homeworld_for(faction)

func get_ownership_count(faction: StringName) -> int:
	return faction_domain.get_ownership_count(faction)

func all_owned_planets(faction: StringName) -> Array[StringName]:
	return faction_domain.all_owned_planets(faction)

func set_starting_workers(planet_id: StringName, count: int) -> void:
	faction_domain.starting_workers[planet_id] = count

func starting_workers_of(planet_id: StringName) -> int:
	return int(faction_domain.starting_workers.get(planet_id, 0))

func discover_planet(faction: StringName, planet_id: StringName) -> bool:
	return faction_domain.discover_planet(faction, planet_id)

func scan_planet(faction: StringName, planet_id: StringName, resource_id: StringName = &"", size_id: StringName = &"", build_slots: int = 0) -> bool:
	return faction_domain.scan_planet(faction, planet_id, resource_id, size_id, build_slots)

func is_known(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_known(planet_id, faction)

func has_scanned_planet(faction: StringName, planet_id: StringName = &"") -> bool:
	return faction_domain.has_scanned_planet(faction, planet_id)

func scan_info_for(faction: StringName, planet_id: StringName) -> Dictionary:
	return faction_domain.scan_info_for(faction, planet_id)

func known_planets_of(faction: StringName) -> Array[StringName]:
	return faction_domain.known_planets_of(faction)

func record_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.record_milestone(faction, milestone_id)

# Lookup by callers using the conflict-manager naming convention.
func mark_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.mark_milestone(faction, milestone_id)

func has_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.has_milestone(faction, milestone_id)

func get_milestones(faction: StringName) -> Dictionary:
	return faction_domain.get_milestones(faction)

func get_starter_scouts(faction: StringName) -> int:
	return faction_domain.get_starter_scouts(faction)

func consume_starter_scout(faction: StringName) -> bool:
	return faction_domain.consume_starter_scout(faction)

# --- ECONOMY & VAULT DELEGATES ---
func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	return economy_domain.get_faction_resource(faction, resource_id)

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	return economy_domain.get_faction_vault_snapshot(faction)

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	return economy_domain.add_faction_resource(faction, resource_id, amount)

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.spend_faction_resource(faction, resource_id, amount)

func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.can_spend_faction_resource(faction, resource_id, amount)

func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	economy_domain.set_planet_resource(planet_id, resource_id)

func resource_of(planet_id: StringName) -> StringName:
	return economy_domain.resource_of(planet_id)

func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.deal_resources(catalog, pool, seed_value)

func resource_snapshot() -> Dictionary:
	return economy_domain.resource_snapshot()

func validate_resources(pool: ResourcePool = null) -> PackedStringArray:
	return economy_domain.validate_resources(pool, faction_domain.homeworlds)

func generate_resources_for_planet(planet_id: StringName, catalog: PlanetUpgradeCatalog = null, base_amount: int = 1) -> int:
	return economy_domain.generate_resources_for_planet(planet_id, faction_domain, tech_domain, catalog, base_amount)

func convert_refinery_resources(planet_id: StringName) -> Dictionary:
	return economy_domain.convert_refinery_resources(planet_id, faction_domain)

func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	return economy_domain.has_planet_upgrade(planet_id, upgrade_id)

func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	return economy_domain.get_planet_upgrades(planet_id)

func can_purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	var faction: StringName = faction_of(planet_id)
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id) if effective_catalog != null else null
	if upgrade == null or (not String(upgrade.required_technology_id).is_empty() and not has_technology(faction, upgrade.required_technology_id)):
		return false
	return economy_domain.can_purchase_upgrade(faction, planet_id, upgrade_id, available_workers, effective_catalog)

func purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	var faction: StringName = faction_of(planet_id)
	if not can_purchase_upgrade(planet_id, upgrade_id, catalog, available_workers):
		return false
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	return economy_domain.purchase_upgrade(faction, planet_id, upgrade_id, available_workers, effective_catalog)

func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	economy_domain.add_planet_upgrade(planet_id, upgrade_id)

func has_worker_factory(planet_id: StringName) -> bool:
	return economy_domain.has_worker_factory(planet_id)

func can_build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int) -> bool:
	var faction: StringName = faction_of(planet_id)
	return economy_domain.can_build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		has_scanned_planet(faction),
		has_technology(faction, TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount
	)

func build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int) -> bool:
	var faction: StringName = faction_of(planet_id)
	return economy_domain.build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		has_scanned_planet(faction),
		has_technology(faction, TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount
	)

func register_gathering_workers(faction: StringName, planet_id: StringName, worker_amount: int, source_planet_id: StringName = &"") -> int:
	if faction == FACTION_NEUTRAL or faction.is_empty() or faction_of(planet_id) != FACTION_NEUTRAL or not has_scanned_planet(faction, planet_id):
		return 0
	economy_domain.register_gathering_workers(faction, planet_id, source_planet_id, worker_amount)
	return economy_domain.gathering_workers_on(faction, planet_id)

func get_gathering_workers(faction: StringName, planet_id: StringName) -> int:
	return economy_domain.gathering_workers_on(faction, planet_id)

func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	return economy_domain.get_gathering_source(faction, planet_id)

func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int) -> int:
	var result: Dictionary = economy_domain.withdraw_gathering_workers(faction, planet_id, amount)
	return int(result.get("count", 0))

func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	return economy_domain.gathering_workers_on(faction, planet_id)

func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	return economy_domain.gather_income_tick(base_amounts, catalog)

# --- TECHNOLOGY DELEGATES ---
func has_technology(faction: StringName, technology_id: StringName) -> bool:
	return tech_domain.has_technology(faction, technology_id)

func get_researched_technologies(faction: StringName) -> Array[StringName]:
	return tech_domain.get_researched_technologies(faction)

func can_research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.can_research_technology(faction, technology_id, cat, economy_domain, faction_domain)

func research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.research_technology(faction, technology_id, cat, economy_domain, faction_domain)

func research_in_progress(faction: StringName, technology_id: StringName) -> bool:
	return tech_domain.research_in_progress(faction, technology_id)

func research_remaining(faction: StringName, technology_id: StringName) -> float:
	return tech_domain.research_remaining(faction, technology_id)

func has_planet_technology(planet_id: StringName, technology_id: StringName) -> bool:
	return tech_domain.has_planet_technology(planet_id, technology_id)

func get_planet_technologies(planet_id: StringName) -> Array[StringName]:
	return tech_domain.get_planet_technologies(planet_id)

func can_research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.can_research_planet_technology(faction, planet_id, technology_id, cat, economy_domain, faction_domain)

func research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.research_planet_technology(faction, planet_id, technology_id, cat, economy_domain, faction_domain)

# --- SHIP & FLEET DELEGATES ---
func get_ship_part_inventory(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_part_inventory(planet_id)

func get_ship_part_count(planet_id: StringName, part_id: StringName) -> int:
	return int(ship_domain.get_ship_part_inventory(planet_id).get(part_id, 0))

func add_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> void:
	ship_domain.add_ship_part(planet_id, part_id, count)

func spend_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> bool:
	return ship_domain.spend_ship_part(planet_id, part_id, count)

func can_buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.can_buy_ship_part(faction, planet_id, part_id, cat, economy_domain, tech_domain)

func buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.buy_ship_part(faction, planet_id, part_id, cat, economy_domain, tech_domain)

func get_ship_assemblies(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_assemblies(planet_id)

func has_ship_assembly(planet_id: StringName, ship_id: StringName) -> bool:
	return ship_domain.has_ship_assembly(planet_id, ship_id)

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> Dictionary:
	return ship_domain.get_ship_assembly(planet_id, ship_id)

func can_assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null, weapon_id: StringName = &"", drive_id: StringName = &"", shield_id: StringName = &"") -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	return ship_domain.can_assemble_ship(planet_id, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id, cat)

func assemble_ship(
	planet_id: StringName,
	hull_id: StringName,
	scanner_id: StringName,
	module_ids: Array,
	catalog: ShipPartCatalog = null,
	weapon_id: StringName = &"",
	drive_id: StringName = &"",
	shield_id: StringName = &"",
	blueprint_id: StringName = &"",
	custom_seed: int = -1,
	ship_role: StringName = &""
) -> StringName:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	return ship_domain.assemble_ship(planet_id, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id, cat, custom_seed, blueprint_id, ship_role)

func disassemble_ship(planet_id: StringName, ship_id: StringName) -> bool:
	return ship_domain.disassemble_ship(planet_id, ship_id)

func launch_ship(planet_id: StringName, ship_id: StringName) -> Dictionary:
	return ship_domain.launch_ship(planet_id, ship_id)

func get_ship_build_jobs(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_build_jobs(planet_id)

func ship_build_in_progress(planet_id: StringName, ship_id: StringName = &"") -> bool:
	return ship_domain.ship_build_in_progress(planet_id, ship_id)

func ship_build_remaining(planet_id: StringName, ship_id: StringName) -> float:
	return ship_domain.ship_build_remaining(planet_id, ship_id)

func create_fleet_from_planet(planet_id: StringName, ship_ids: Array, catalog: ShipPartCatalog = null) -> FleetSnapshot:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.create_fleet_from_planet(planet_id, ship_ids, faction, cat)

func preview_fleet_from_planet(planet_id: StringName, ship_ids: Array, catalog: ShipPartCatalog = null) -> FleetSnapshot:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.preview_fleet_from_planet(planet_id, ship_ids, faction, cat)

func disband_fleet_to_planet(fleet: FleetSnapshot, planet_id: StringName) -> void:
	ship_domain.disband_fleet_to_planet(fleet, planet_id)

func reconcile_defender_fleet(planet_id: StringName, defender_fleet: FleetSnapshot, surviving: Array) -> void:
	ship_domain.reconcile_defender_fleet(planet_id, defender_fleet, surviving)

# --- VALIDATION HELPERS ---
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for p_id in faction_domain.ownership:
		var faction: StringName = faction_domain.ownership[p_id]
		if faction != FACTION_PLAYER and faction != FACTION_CPU and faction != FACTION_NEUTRAL:
			errors.append("Invalid faction for planet %s: %s" % [p_id, faction])
	return errors

func validate_starting_setup() -> PackedStringArray:
	var errors := PackedStringArray()
	if homeworld_for(FACTION_PLAYER) == &"":
		errors.append("Missing player homeworld")
	if homeworld_for(FACTION_CPU) == &"":
		errors.append("Missing CPU homeworld")
	return errors
