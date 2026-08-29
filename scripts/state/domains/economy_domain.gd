class_name EconomyDomain
extends RefCounted

## Manages faction vaults, resource deals, planet upgrades, worker factories, and gathering state.

const DEFAULT_ECONOMY_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

var economy_config: EconomyConfig = DEFAULT_ECONOMY_CONFIG
var _next_trade_route_index: int = 0
var market_prices: Dictionary = {}
var trade_volumes: Dictionary = {}
var worker_transport_records: Dictionary = {}
var _next_worker_transport_index: int = 0

# These signals are emitted by the economy unit files (vault_core, upgrade_unit,
# refinery_trade_unit) via _owner.<signal>.emit(...); the linter only sees the
# declarations here and flags them as unused. worker_factory_built/building_* are
# emitted in-class and therefore not annotated.
@warning_ignore("unused_signal")
signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
@warning_ignore("unused_signal")
signal credits_changed(faction: StringName, new_amount: int)
@warning_ignore("unused_signal")
signal workers_reserved(planet_id: StringName, job_id: StringName, amount: int)
@warning_ignore("unused_signal")
signal workers_released(planet_id: StringName, job_id: StringName, amount: int)
@warning_ignore("unused_signal")
signal planet_upgraded(planet_id: StringName, upgrade_id: StringName)
@warning_ignore("unused_signal")
signal resource_generated(planet_id: StringName, resource_id: StringName, amount: int)
@warning_ignore("unused_signal")
signal resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int)
@warning_ignore("unused_signal")
signal gathering_started(faction: StringName, planet_id: StringName, workers: int)
@warning_ignore("unused_signal")
signal gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int)
@warning_ignore("unused_signal")
signal worker_factory_built(planet_id: StringName)
@warning_ignore("unused_signal")
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
@warning_ignore("unused_signal")
signal local_resources_changed(planet_id: StringName, resource_id: StringName, new_amount: int)
@warning_ignore("unused_signal")
signal resource_transferred(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int)
@warning_ignore("unused_signal")
signal building_placed(planet_id: StringName, building_id: StringName, q: int, r: int)
@warning_ignore("unused_signal")
signal building_removed(planet_id: StringName, q: int, r: int)
@warning_ignore("unused_signal")
signal worker_transport_started(transport_id: StringName, faction: StringName, amount: int)
@warning_ignore("unused_signal")
signal worker_transport_phase_changed(transport_id: StringName, phase: StringName)


var faction_vaults: Dictionary = {}
var faction_credits: Dictionary = {}
var worker_reservations: Dictionary = {}
var upgrade_build_jobs: Dictionary = {}
var planet_resources: Dictionary = {}
var planet_upgrades: Dictionary = {}
var worker_factories: Dictionary = {}
var gathering_workers: Dictionary = {}
var gathering_sources: Dictionary = {}
var local_vaults: Dictionary = {}
var trade_routes: Dictionary = {}
var planet_buildings: Dictionary = {}
var building_jobs: Dictionary = {}
# Planets whose starting local stock has already been dealt (prevents
# re-seeding when an evicted chunk is regenerated).
var _local_seeded_planets: Dictionary = {}

## R-007 (E1): Verhaltens-Einheit für Vaults/Credits/Local-Vaults/Reservierungen.
## Der State bleibt auf dieser Fassade; die Einheit mutiert ihn über _owner,
## damit Dictionary-Referenzsemantik und Signal-Identität erhalten bleiben.
var _vault_core: EconomyVaultCore

## E2: Verhaltens-Einheiten für Resource-Dealing und Planeten-Upgrades.
var _deal_unit: EconomyDealUnit
var _upgrade_unit: EconomyUpgradeUnit
## E3: Verhaltens-Einheit für Refinery, Trade, Gathering und Resource-Generierung.
var _refinery_trade_unit: EconomyRefineryTradeUnit
## E4a: Verhaltens-Einheit für Gathering und Worker-Transport.
var _gathering_transport_unit: EconomyGatheringTransportUnit
## E4b: Verhaltens-Einheit für Worker-Fabriken.
var _worker_factory_unit: EconomyWorkerFactoryUnit
## E4b: Verhaltens-Einheit für Gebäude auf dem Grid inkl. Baustellen-Queue.
var _buildings_unit: EconomyBuildingsUnit


func _init() -> void:
	_vault_core = EconomyVaultCore.new(self)
	_deal_unit = EconomyDealUnit.new(self)
	_upgrade_unit = EconomyUpgradeUnit.new(self)
	_refinery_trade_unit = EconomyRefineryTradeUnit.new(self)
	_gathering_transport_unit = EconomyGatheringTransportUnit.new(self)
	_worker_factory_unit = EconomyWorkerFactoryUnit.new(self)
	_buildings_unit = EconomyBuildingsUnit.new(self)


## Injiziert den Route-Owner-Resolver (GameState->_init ruft das mit
## self.faction_of). Ohne Injektion liefern Trade-Routen FACTION_NEUTRAL
## als Owner — identisches Verhalten für synthetische Headless-Test-Planeten.
func set_route_owner_resolver(resolver: Callable) -> void:
	_gathering_transport_unit.set_route_owner_resolver(resolver)


func reset_vaults() -> void:
	_vault_core.reset_vaults()

func reset() -> void:
	_vault_core.reset()

func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.credit_transport_resources(faction, resource_id, amount)

func get_faction_credits(faction: StringName) -> int:
	return _vault_core.get_faction_credits(faction)

## Creates the data-side record for a physical worker round-trip. The visible
## WorkerCluster is disposable; this record is the source of truth across
## chunk cycling and scene rebuilds.
func begin_worker_transport(faction: StringName, source_planet_id: StringName, destination_planet_id: StringName, amount: int, duration: float, route_path: Array[Vector2]) -> StringName:
	return _gathering_transport_unit.begin_worker_transport(faction, source_planet_id, destination_planet_id, amount, duration, route_path)

func update_worker_transport(transport_id: StringName, phase: StringName, cargo_resource_id: StringName = &"", cargo_amount: int = 0) -> bool:
	return _gathering_transport_unit.update_worker_transport(transport_id, phase, cargo_resource_id, cargo_amount)

func set_worker_transport_escorted(transport_id: StringName, escorted: bool = true) -> bool:
	return _gathering_transport_unit.set_worker_transport_escorted(transport_id, escorted)

func get_worker_transport_records(faction: StringName = &"") -> Array[Dictionary]:
	return _gathering_transport_unit.get_worker_transport_records(faction)

func complete_worker_transport(transport_id: StringName, delivered: bool = true) -> bool:
	return _gathering_transport_unit.complete_worker_transport(transport_id, delivered)

func add_faction_credits(faction: StringName, amount: int) -> int:
	return _vault_core.add_faction_credits(faction, amount)

func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return _vault_core.can_spend_faction_credits(faction, amount)

func spend_faction_credits(faction: StringName, amount: int) -> bool:
	return _vault_core.spend_faction_credits(faction, amount)

func can_spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return _vault_core.can_spend_cost(faction, resource_id, resource_amount, credit_amount)

func spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return _vault_core.spend_cost(faction, resource_id, resource_amount, credit_amount)

func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	return _vault_core.get_faction_resource(faction, resource_id)

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	return _vault_core.get_faction_vault_snapshot(faction)

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	return _vault_core.add_faction_resource(faction, resource_id, amount)

func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.can_spend_faction_resource(faction, resource_id, amount)

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.spend_faction_resource(faction, resource_id, amount)

func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	_vault_core.set_planet_resource(planet_id, resource_id)

func resource_of(planet_id: StringName) -> StringName:
	return _vault_core.resource_of(planet_id)

## E2: Delegation an EconomyDealUnit.
func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_deal_unit.deal_resources(catalog, pool, seed_value)

## E2: Delegation an EconomyDealUnit.
func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_deal_unit.deal_resources_for_planets(planet_data, pool, seed_value)

## E2: Delegation an EconomyDealUnit.
func validate_resources(pool: ResourcePool = null, homeworlds: Dictionary = {}) -> PackedStringArray:
	return _deal_unit.validate_resources(pool, homeworlds)

func resource_snapshot() -> Dictionary:
	return _vault_core.resource_snapshot()

func available_workers(planet_id: StringName, total_workers: int) -> int:
	return _vault_core.available_workers(planet_id, total_workers)

func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	return _vault_core.reserve_workers(planet_id, job_id, amount, total_workers)

func release_workers(planet_id: StringName, job_id: StringName) -> int:
	return _vault_core.release_workers(planet_id, job_id)

## E2: Delegation an EconomyUpgradeUnit.
func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	return _upgrade_unit.can_purchase_upgrade(faction, planet_id, upgrade_id, available_worker_count, catalog)

## E2: Delegation an EconomyUpgradeUnit.
func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	return _upgrade_unit.purchase_upgrade(faction, planet_id, upgrade_id, available_worker_count, catalog)

## E2: Delegation an EconomyUpgradeUnit.
func can_purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	return _upgrade_unit.can_purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_worker_count)

## E2: Delegation an EconomyUpgradeUnit.
func purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	return _upgrade_unit.purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_worker_count)

## E2: Delegation an EconomyUpgradeUnit.
func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	return _upgrade_unit.upgrade_build_in_progress(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	return _upgrade_unit.upgrade_build_remaining(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func advance_upgrade_builds(delta: float) -> void:
	_upgrade_unit.advance_upgrade_builds(delta)

## E2: Delegation an EconomyUpgradeUnit.
func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	return _upgrade_unit.abort_upgrade_build(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	return _upgrade_unit.has_planet_upgrade(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	return _upgrade_unit.get_planet_upgrades(planet_id)

## E2: Delegation an EconomyUpgradeUnit.
func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	_upgrade_unit.add_planet_upgrade(planet_id, upgrade_id)

## E4b: Delegation an EconomyWorkerFactoryUnit.
func has_worker_factory(planet_id: StringName) -> bool:
	return _worker_factory_unit.has_worker_factory(planet_id)

## E4b: Delegation an EconomyWorkerFactoryUnit.
func can_build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	return _worker_factory_unit.can_build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots, cost_resource, cost_amount, credit_cost)

## E4b: Delegation an EconomyWorkerFactoryUnit.
func build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	return _worker_factory_unit.build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots, cost_resource, cost_amount, credit_cost)

## E4b: Delegation an EconomyWorkerFactoryUnit.
func can_build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	return _worker_factory_unit.can_build_worker_factory_with_domains(planet_id, faction_domain, tech_domain, cost_resource, cost_amount, credit_cost)

## E4b: Delegation an EconomyWorkerFactoryUnit.
func build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	return _worker_factory_unit.build_worker_factory_with_domains(planet_id, faction_domain, tech_domain, cost_resource, cost_amount, credit_cost)

## E3: Delegation an EconomyRefineryTradeUnit.
func steal_resources(planet_id: StringName, attacker_faction: StringName, percentage: float = 0.5) -> Dictionary:
	return _refinery_trade_unit.steal_resources(planet_id, attacker_faction, percentage)

## E4a: Delegation an EconomyGatheringTransportUnit.
func register_gathering_workers(faction: StringName, planet_id: StringName, source_planet_id: StringName, count: int) -> void:
	_gathering_transport_unit.register_gathering_workers(faction, planet_id, source_planet_id, count)

## E4a: Delegation an EconomyGatheringTransportUnit.
func register_gathering_workers_with_domains(
	faction: StringName,
	planet_id: StringName,
	worker_amount: int,
	faction_domain: FactionDomain,
	source_planet_id: StringName = &""
) -> int:
	return _gathering_transport_unit.register_gathering_workers_with_domains(faction, planet_id, worker_amount, faction_domain, source_planet_id)

## E4a: Delegation an EconomyGatheringTransportUnit.
func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	return _gathering_transport_unit.get_gathering_source(faction, planet_id)

## E4a: Delegation an EconomyGatheringTransportUnit.
func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int = -1) -> Dictionary:
	return _gathering_transport_unit.withdraw_gathering_workers(faction, planet_id, amount)

## E4a: Delegation an EconomyGatheringTransportUnit.
func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	return _gathering_transport_unit.gathering_workers_on(faction, planet_id)

## E4a: Delegation an EconomyGatheringTransportUnit.
func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	return _gathering_transport_unit.gather_income_tick(base_amounts, catalog)

## E4a: Delegation an EconomyGatheringTransportUnit.
func generate_resources_for_planet(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech: TechDomain,
	catalog: PlanetUpgradeCatalog,
	base_amount: int = 1
) -> int:
	return _gathering_transport_unit.generate_resources_for_planet(planet_id, faction_domain, tech, catalog, base_amount)

## E3: Delegation an EconomyRefineryTradeUnit.
func convert_refinery_resources(planet_id: StringName, faction_domain: FactionDomain) -> Dictionary:
	return _refinery_trade_unit.convert_refinery_resources(planet_id, faction_domain)

# Local copy of GameState.is_valid_resource — calling the static via the autoload
# instance triggers a STATIC_CALLED_ON_INSTANCE warning under Godot's parser.
func _is_valid_resource_id(resource_id: StringName) -> bool:
	return _vault_core.is_valid_resource_id(resource_id)

# --- LOCAL VAULTS (per-planet) ---

func local_vault(planet_id: StringName) -> Dictionary:
	return _vault_core.local_vault(planet_id)

func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return _vault_core.get_local_resource(planet_id, resource_id)

func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	return _vault_core.add_local_resource(planet_id, resource_id, amount)

func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.spend_local_resource(planet_id, resource_id, amount)

func transfer_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.transfer_resources(from_planet, to_planet, resource_id, amount)

## Seeds a small deterministic starting stock of each planet's own resource.
func seed_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_vault_core.seed_local_resources(planet_ids, pool, seed_value)

# --- BUILDINGS ON GRID ---

## E4b: Delegation an EconomyBuildingsUnit.
func can_spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	return _buildings_unit.can_spend_building_cost(faction, building)

## E4b: Delegation an EconomyBuildingsUnit.
func spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	return _buildings_unit.spend_building_cost(faction, building)

## E4b: Delegation an EconomyBuildingsUnit.
func queue_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int, faction: StringName, reservation_id: StringName, build_time: float, costs: Dictionary) -> bool:
	return _buildings_unit.queue_planet_building(planet_id, building_id, q, r, faction, reservation_id, build_time, costs)

## E4b: Delegation an EconomyBuildingsUnit.
func building_job_in_progress(planet_id: StringName, q: int, r: int) -> bool:
	return _buildings_unit.building_job_in_progress(planet_id, q, r)

## E4b: Delegation an EconomyBuildingsUnit.
func advance_building_jobs(delta: float) -> void:
	_buildings_unit.advance_building_jobs(delta)

## E4b: Delegation an EconomyBuildingsUnit.
func abort_building_job(planet_id: StringName, q: int, r: int) -> bool:
	return _buildings_unit.abort_building_job(planet_id, q, r)

## E4b: Delegation an EconomyBuildingsUnit.
func record_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int) -> void:
	_buildings_unit.record_planet_building(planet_id, building_id, q, r)

## E4b: Delegation an EconomyBuildingsUnit.
func remove_planet_building(planet_id: StringName, q: int, r: int) -> StringName:
	return _buildings_unit.remove_planet_building(planet_id, q, r)

## E4b: Delegation an EconomyBuildingsUnit.
func can_place_building(planet_id: StringName, building_id: StringName, faction_domain: FactionDomain, tech_domain: TechDomain, catalog: BuildingCatalog = null) -> bool:
	return _buildings_unit.can_place_building(planet_id, building_id, faction_domain, tech_domain, catalog)

## E4b: Delegation an EconomyBuildingsUnit.
func place_building(planet_id: StringName, building_id: StringName, q: int, r: int, faction_domain: FactionDomain, tech_domain: TechDomain, catalog: BuildingCatalog = null) -> bool:
	return _buildings_unit.place_building(planet_id, building_id, q, r, faction_domain, tech_domain, catalog)

## E4b: Delegation an EconomyBuildingsUnit.
func planet_building_at(planet_id: StringName, q: int, r: int) -> StringName:
	return _buildings_unit.planet_building_at(planet_id, q, r)

## E4b: Delegation an EconomyBuildingsUnit.
func planet_buildings_of(planet_id: StringName) -> Dictionary:
	return _buildings_unit.planet_buildings_of(planet_id)

# --- TRADE ROUTES ---

## E3: Delegation an EconomyRefineryTradeUnit.
func can_register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> bool:
	return _refinery_trade_unit.can_register_trade_route(from_planet, to_planet, resource_id)

## E3: Delegation an EconomyRefineryTradeUnit.
func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	return _refinery_trade_unit.register_trade_route(from_planet, to_planet, resource_id)

## E3: Delegation an EconomyRefineryTradeUnit.
func market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	return _refinery_trade_unit.market_price(from_planet, to_planet, resource_id)

## E3: Delegation an EconomyRefineryTradeUnit.
func get_market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	return _refinery_trade_unit.get_market_price(from_planet, to_planet, resource_id)

## E3: Delegation an EconomyRefineryTradeUnit.
func trade_routes_snapshot() -> Dictionary:
	return _refinery_trade_unit.trade_routes_snapshot()

## E3: Delegation an EconomyRefineryTradeUnit.
func tick_trade_routes() -> int:
	return _refinery_trade_unit.tick_trade_routes()

## E3: Delegation an EconomyRefineryTradeUnit.
func market_snapshot() -> Dictionary:
	return _refinery_trade_unit.market_snapshot()

func capture_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	data.faction_vaults = faction_vaults.duplicate(true)
	data.faction_credits = faction_credits.duplicate(true)
	data.worker_reservations = worker_reservations.duplicate(true)
	data.upgrade_build_jobs = upgrade_build_jobs.duplicate(true)
	data.planet_resources = planet_resources.duplicate(true)
	data.planet_upgrades = planet_upgrades.duplicate(true)
	data.worker_factories = worker_factories.duplicate(true)
	data.gathering_workers = gathering_workers.duplicate(true)
	data.gathering_sources = gathering_sources.duplicate(true)
	data.local_vaults = local_vaults.duplicate(true)
	data.trade_routes = trade_routes.duplicate(true)
	data.planet_buildings = planet_buildings.duplicate(true)
	data.building_jobs = building_jobs.duplicate(true)
	data.local_seeded_planets = _local_seeded_planets.duplicate(true)
	data.worker_transport_records = worker_transport_records.duplicate(true)
	data.next_trade_route_index = _next_trade_route_index
	data.next_worker_transport_index = _next_worker_transport_index

func restore_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	reset()
	faction_vaults = RunSaveData.restore_dict(data.faction_vaults)
	faction_credits = RunSaveData.restore_dict(data.faction_credits)
	worker_reservations = RunSaveData.restore_dict(data.worker_reservations)
	upgrade_build_jobs = RunSaveData.restore_dict(data.upgrade_build_jobs)
	planet_resources = RunSaveData.restore_dict(data.planet_resources)
	planet_upgrades = RunSaveData.restore_dict(data.planet_upgrades)
	worker_factories = RunSaveData.restore_dict(data.worker_factories)
	gathering_workers = RunSaveData.restore_dict(data.gathering_workers)
	gathering_sources = RunSaveData.restore_dict(data.gathering_sources)
	local_vaults = RunSaveData.restore_dict(data.local_vaults)
	trade_routes = RunSaveData.restore_dict(data.trade_routes)
	planet_buildings = RunSaveData.restore_dict(data.planet_buildings)
	building_jobs = RunSaveData.restore_dict(data.building_jobs)
	_local_seeded_planets = RunSaveData.restore_dict(data.local_seeded_planets)
	worker_transport_records = RunSaveData.restore_dict(data.worker_transport_records)
	_next_trade_route_index = data.next_trade_route_index
	_next_worker_transport_index = data.next_worker_transport_index
