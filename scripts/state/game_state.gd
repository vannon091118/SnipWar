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
const DEFAULT_BUILDING_CATALOG: BuildingCatalog = preload("res://resources/config/building_catalog_default.tres")

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)
signal catalog_reset(catalog: PlanetCatalog)
signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal credits_changed(faction: StringName, new_amount: int)
signal workers_reserved(planet_id: StringName, job_id: StringName, amount: int)
signal workers_released(planet_id: StringName, job_id: StringName, amount: int)
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
signal mid_game_started(faction: StringName)
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
signal research_started(faction: StringName, technology_id: StringName, remaining: float)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)
signal research_ship_task_completed(mission_id: StringName, target_planet_id: StringName, task_type: StringName)
signal research_ship_idle(ship_id: StringName, planet_id: StringName)
signal persistent_ship_changed(ship_id: StringName, status: StringName)
signal battle_context_changed(context: BattleContext)
signal transit_changed(record: TransitRecord)
signal run_started(run_id: StringName, layout_seed: int)
signal planet_building_placed(planet_id: StringName, q: int, r: int, building_id: StringName)
signal planet_building_destroyed(planet_id: StringName, q: int, r: int)
signal resource_transferred(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int)
signal worker_transport_started(transport_id: StringName, faction: StringName, amount: int)
signal worker_transport_phase_changed(transport_id: StringName, phase: StringName)
signal local_resources_changed(planet_id: StringName, resource_id: StringName, new_amount: int)

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
var _run_active: bool = false
var _run_id: StringName = &""
var _run_scenario_id: StringName = &""
var _run_layout_seed: int = 0
var _run_infinite_world: bool = false
var _pending_battle: BattleContext
var _transit_records: Dictionary = {}
var _next_transit_index: int = 0
var _reconnect_requested: bool = false
# Typed context bridge between scenes (world session + save/load handover).
var _session: RunSession
# Pending chunk/timer payload handed to the world scene after a save restore.
var _pending_chunk_data: ChunkSaveData
var _pending_timers: Dictionary = {}

func _init() -> void:
	_connect_domain_signals()
	economy_domain.reset_vaults()
	_session = RunSession.new()

func _connect_domain_signals() -> void:
	# Typed signals in Godot 4.x must be forwarded with explicit arg lists, so
	# each connection lists the source/domain and target/facade pair.
	faction_domain.faction_changed.connect(_on_domain_faction_changed)
	faction_domain.planet_discovered.connect(func(f, p): planet_discovered.emit(f, p))
	faction_domain.planet_scanned.connect(func(f, p, r, s, b): planet_scanned.emit(f, p, r, s, b))
	faction_domain.milestone_reached.connect(_on_domain_milestone_reached)

	economy_domain.faction_resources_changed.connect(func(f, r, a): faction_resources_changed.emit(f, r, a))
	economy_domain.credits_changed.connect(func(f, a): credits_changed.emit(f, a))
	economy_domain.workers_reserved.connect(func(p, j, a): workers_reserved.emit(p, j, a))
	economy_domain.workers_released.connect(func(p, j, a): workers_released.emit(p, j, a))
	economy_domain.planet_upgraded.connect(func(p, u): planet_upgraded.emit(p, u))
	economy_domain.resource_generated.connect(func(p, r, a): resource_generated.emit(p, r, a))
	economy_domain.resources_collected.connect(func(f, p, r, a): resources_collected.emit(f, p, r, a))
	economy_domain.gathering_started.connect(func(f, p, w): gathering_started.emit(f, p, w))
	economy_domain.gathering_withdrawn.connect(func(f, p, w): gathering_withdrawn.emit(f, p, w))
	economy_domain.worker_factory_built.connect(func(p): worker_factory_built.emit(p))
	economy_domain.refinery_converted.connect(func(p, f, c, pr): refinery_converted.emit(p, f, c, pr))
	economy_domain.local_resources_changed.connect(func(p, r, a): local_resources_changed.emit(p, r, a))
	economy_domain.resource_transferred.connect(func(f, t, r, a): resource_transferred.emit(f, t, r, a))
	economy_domain.building_placed.connect(func(p, b, q, r): planet_building_placed.emit(p, q, r, b))
	economy_domain.building_removed.connect(func(p, q, r): planet_building_destroyed.emit(p, q, r))

	tech_domain.technology_researched.connect(func(f, t): technology_researched.emit(f, t))
	tech_domain.planet_technology_researched.connect(func(p, t): planet_technology_researched.emit(p, t))
	tech_domain.research_started.connect(func(f, t, r): research_started.emit(f, t, r))

	ship_domain.ship_part_purchased.connect(func(p, pt): ship_part_purchased.emit(p, pt))
	ship_domain.ship_assembled.connect(_on_ship_assembled_domain)
	ship_domain.ship_disassembled.connect(func(p, s): ship_disassembled.emit(p, s))
	ship_domain.ship_launched.connect(func(p, s, r): ship_launched.emit(p, s, r))
	ship_domain.ship_lost.connect(func(p, s): ship_lost.emit(p, s))
	ship_domain.ship_build_started.connect(func(p, s, r): ship_build_started.emit(p, s, r))
	ship_domain.research_ship_task_completed.connect(func(m, p, t): research_ship_task_completed.emit(m, p, t))
	ship_domain.research_ship_idle.connect(func(s, p): research_ship_idle.emit(s, p))
	ship_domain.persistent_ship_changed.connect(func(s, status): persistent_ship_changed.emit(s, status))

func _on_ship_assembled_domain(planet_id: StringName, ship_id: StringName) -> void:
	economy_domain.release_workers(planet_id, ship_id)
	ship_assembled.emit(planet_id, ship_id)
	mark_milestone(faction_of(planet_id), &"first_ship")

func _on_domain_faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	faction_changed.emit(planet_id, old_faction, new_faction)
	if new_faction != FACTION_NEUTRAL and get_ownership_count(new_faction) >= 2:
		mark_milestone(new_faction, &"second_planet")

func _on_domain_milestone_reached(faction: StringName, milestone_id: StringName) -> void:
	milestone_reached.emit(faction, milestone_id)
	if faction == FACTION_PLAYER and milestone_id == &"second_planet":
		mid_game_started.emit(faction)

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	faction_domain.reset(catalog)
	economy_domain.reset()
	tech_domain.reset()
	ship_domain.reset()
	_transit_records.clear()
	_pending_battle = null
	catalog_reset.emit(catalog)

func reset_for_infinite_world() -> void:
	faction_domain.reset_infinite()
	economy_domain.reset()
	tech_domain.reset()
	ship_domain.reset()
	_transit_records.clear()
	_pending_battle = null
	catalog_reset.emit(null)

## Starts a new run and is the only public path that resets domain state.
func begin_new_game(catalog: PlanetCatalog, scenario_id: StringName, layout_seed: int, infinite_world: bool = false) -> void:
	_run_active = true
	_run_id = StringName("run_%d" % layout_seed)
	_run_scenario_id = scenario_id
	_run_layout_seed = layout_seed
	_run_infinite_world = infinite_world
	_reconnect_requested = false
	_pending_chunk_data = null
	_pending_timers.clear()
	_sync_session()
	if infinite_world:
		reset_for_infinite_world()
	else:
		reset_from_catalog(catalog)
	var player_homeworld: StringName = faction_domain.homeworld_for(FACTION_PLAYER)
	ship_domain.ensure_starter_research_ship(FACTION_PLAYER, player_homeworld, DEFAULT_SHIP_PART_CATALOG)
	run_started.emit(_run_id, _run_layout_seed)

## Reconnects a newly loaded world scene to this run without mutating any
## faction, economy, technology, or ship-domain data.
func reconnect_world(scenario_id: StringName, layout_seed: int, infinite_world: bool = false) -> bool:
	if not _run_active:
		return false
	if not String(scenario_id).is_empty():
		_run_scenario_id = scenario_id
	_run_layout_seed = layout_seed
	_run_infinite_world = infinite_world
	_sync_session()
	return true

func request_world_reconnect() -> void:
	_reconnect_requested = true

func consume_world_reconnect_request() -> bool:
	var requested := _reconnect_requested
	_reconnect_requested = false
	return requested

func has_active_run() -> bool:
	return _run_active

func run_id() -> StringName:
	return _run_id

## Typed session bridge (scenario, seed, world mode) shared across scenes.
func session() -> RunSession:
	if _session == null:
		_session = RunSession.new()
	return _session

## Clears the active run so the next world boot starts a fresh game instead of
## reconnecting. Called by the main menu's "Neues Spiel" flow.
func request_new_run() -> void:
	_run_active = false
	_reconnect_requested = false
	_run_id = &""
	_run_scenario_id = &""
	_run_layout_seed = 0
	_run_infinite_world = false
	_pending_chunk_data = null
	_pending_timers.clear()
	if _session != null:
		_session.run_id = &""

func world_session_context() -> Dictionary:
	return {
		"run_id": _run_id,
		"scenario_id": _run_scenario_id,
		"layout_seed": _run_layout_seed,
		"infinite_world": _run_infinite_world,
	}

func _sync_session() -> void:
	if _session == null:
		_session = RunSession.new()
	_session.run_id = _run_id
	_session.scenario_id = _run_scenario_id
	_session.layout_seed = _run_layout_seed
	_session.infinite_world = _run_infinite_world
	if _session.started_at <= 0:
		_session.started_at = int(Time.get_unix_time_from_system())

func set_pending_battle_context(context: BattleContext) -> void:
	_pending_battle = context.copy() if context != null else null
	battle_context_changed.emit(_pending_battle)

func pending_battle_context() -> BattleContext:
	return _pending_battle.copy() if _pending_battle != null else null

func clear_pending_battle_context(battle_id: StringName = &"") -> void:
	if _pending_battle == null:
		return
	if not String(battle_id).is_empty() and _pending_battle.battle_id != battle_id:
		return
	_pending_battle = null
	battle_context_changed.emit(null)

func register_transit(record: TransitRecord) -> bool:
	if record == null or String(record.transit_id).is_empty():
		return false
	_transit_records[record.transit_id] = record.copy()
	transit_changed.emit(record)
	return true

func update_transit(record: TransitRecord) -> bool:
	return register_transit(record)

func remove_transit(transit_id: StringName) -> void:
	_transit_records.erase(transit_id)

func get_transit(transit_id: StringName) -> TransitRecord:
	var record: TransitRecord = _transit_records.get(transit_id) as TransitRecord
	return record.copy() if record != null else null

func get_transit_records() -> Array[TransitRecord]:
	var result: Array[TransitRecord] = []
	for value in _transit_records.values():
		var record: TransitRecord = value as TransitRecord
		if record != null:
			result.append(record.copy())
	return result

func next_transit_id() -> StringName:
	_next_transit_index += 1
	return StringName("transit_%d" % _next_transit_index)

func set_jobs_auto_advance(auto_advance: bool) -> void:
	_jobs_auto_advance = auto_advance

func advance_upgrade_builds(delta: float) -> void:
	economy_domain.advance_upgrade_builds(delta)

func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	return economy_domain.upgrade_build_in_progress(planet_id, upgrade_id)

func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	return economy_domain.upgrade_build_remaining(planet_id, upgrade_id)

func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	return economy_domain.abort_upgrade_build(planet_id, upgrade_id)

func advance_building_jobs(delta: float) -> void:
	economy_domain.advance_building_jobs(delta)

func building_job_in_progress(planet_id: StringName, q: int, r: int) -> bool:
	return economy_domain.building_job_in_progress(planet_id, q, r)

func abort_building_job(planet_id: StringName, q: int, r: int) -> bool:
	return economy_domain.abort_building_job(planet_id, q, r)

func advance_research(delta: float) -> void:
	tech_domain.advance_research(delta)

func advance_builds(delta: float) -> void:
	ship_domain.advance_builds(delta)

func advance_research_ship_tasks(delta: float) -> void:
	ship_domain.advance_research_ship_tasks(delta)

func _process(delta: float) -> void:
	if _jobs_auto_advance:
		advance_research(delta)
		advance_builds(delta)
		economy_domain.advance_upgrade_builds(delta)
		economy_domain.advance_building_jobs(delta)
		ship_domain.advance_research_ship_tasks(delta)

# --- FACTION & OWNERSHIP DELEGATES ---
func set_faction(planet_id: StringName, faction: StringName) -> void:
	faction_domain.set_faction(planet_id, faction)

func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	faction_domain.register_planet(planet_id, initial_faction)

func register_homeworld(faction: StringName, planet_id: StringName) -> void:
	faction_domain.register_homeworld(faction, planet_id)

func seed_starting_workers(planet_id: StringName, profile: PlanetSizeProfile) -> void:
	faction_domain.seed_starting_workers(planet_id, profile)

func faction_of(planet_id: StringName) -> StringName:
	return faction_domain.faction_of(planet_id)

func is_owned_by(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_owned_by(planet_id, faction)

func homeworld_for(faction: StringName) -> StringName:
	return faction_domain.homeworld_for(faction)

func get_ownership_count(faction: StringName) -> int:
	return faction_domain.get_ownership_count(faction)

func all_owned_planets(faction: StringName) -> Array[StringName]:
	return faction_domain.all_owned_planets(faction)

func starting_workers_of(planet_id: StringName) -> int:
	return int(faction_domain.starting_workers.get(planet_id, 0))

func add_starting_workers(planet_id: StringName, amount: int) -> void:
	faction_domain.add_starting_workers(planet_id, amount)

func discover_planet(faction: StringName, planet_id: StringName) -> bool:
	return faction_domain.discover_planet(faction, planet_id)

func scan_planet(faction: StringName, planet_id: StringName, resource_id: StringName = &"", size_id: StringName = &"", build_slots: int = 0) -> bool:
	var newly_scanned: bool = faction_domain.scan_planet(faction, planet_id, resource_id, size_id, build_slots)
	if newly_scanned:
		mark_milestone(faction, &"first_scan")
	return newly_scanned

func is_known(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_known(planet_id, faction)

func has_scanned_planet(faction: StringName, planet_id: StringName = &"") -> bool:
	return faction_domain.has_scanned_planet(faction, planet_id)

func scan_info_for(faction: StringName, planet_id: StringName) -> Dictionary:
	return faction_domain.scan_info_for(faction, planet_id)

func known_planets_of(faction: StringName) -> Array[StringName]:
	return faction_domain.known_planets_of(faction)

# Lookup by callers using the conflict-manager naming convention.
func mark_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.mark_milestone(faction, milestone_id)

func has_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.has_milestone(faction, milestone_id)

func get_milestones(faction: StringName) -> Dictionary:
	return faction_domain.get_milestones(faction)

# --- ECONOMY & VAULT DELEGATES ---
func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	var credited: bool = economy_domain.credit_transport_resources(faction, resource_id, amount)
	if credited:
		mark_milestone(faction, &"first_transport")
	return credited

func get_faction_credits(faction: StringName) -> int:
	return economy_domain.get_faction_credits(faction)

func add_faction_credits(faction: StringName, amount: int) -> int:
	return economy_domain.add_faction_credits(faction, amount)

func spend_faction_credits(faction: StringName, amount: int) -> bool:
	return economy_domain.spend_faction_credits(faction, amount)

func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return economy_domain.can_spend_faction_credits(faction, amount)

func can_spend_faction_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return economy_domain.can_spend_cost(faction, resource_id, resource_amount, credit_amount)

func begin_worker_transport(faction: StringName, source_planet_id: StringName, destination_planet_id: StringName, amount: int, duration: float, route_path: Array[Vector2]) -> StringName:
	var transport_id: StringName = economy_domain.begin_worker_transport(faction, source_planet_id, destination_planet_id, amount, duration, route_path)
	if not String(transport_id).is_empty():
		worker_transport_started.emit(transport_id, faction, amount)
	return transport_id

func update_worker_transport(transport_id: StringName, phase: StringName, cargo_resource_id: StringName = &"", cargo_amount: int = 0) -> bool:
	var updated: bool = economy_domain.update_worker_transport(transport_id, phase, cargo_resource_id, cargo_amount)
	if updated:
		worker_transport_phase_changed.emit(transport_id, phase)
	return updated

func set_worker_transport_escorted(transport_id: StringName, escorted: bool = true) -> bool:
	return economy_domain.set_worker_transport_escorted(transport_id, escorted)

func get_worker_transport_records(faction: StringName = &"") -> Array[Dictionary]:
	return economy_domain.get_worker_transport_records(faction)

func complete_worker_transport(transport_id: StringName, delivered: bool = true) -> bool:
	var completed: bool = economy_domain.complete_worker_transport(transport_id, delivered)
	if completed:
		worker_transport_phase_changed.emit(transport_id, &"delivered" if delivered else &"cancelled")
	return completed

func get_market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	return economy_domain.get_market_price(from_planet, to_planet, resource_id)

func market_snapshot() -> Dictionary:
	return economy_domain.market_snapshot()

func spend_faction_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return economy_domain.spend_cost(faction, resource_id, resource_amount, credit_amount)

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

func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.deal_resources_for_planets(planet_data, pool, seed_value)

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
	var workforce: int = available_workers
	if workforce < 0 and faction_domain.starting_workers.has(planet_id):
		workforce = int(faction_domain.starting_workers.get(planet_id, 0))
	return economy_domain.can_purchase_upgrade(faction, planet_id, upgrade_id, workforce, effective_catalog)

func purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	var faction: StringName = faction_of(planet_id)
	if not can_purchase_upgrade(planet_id, upgrade_id, catalog, available_workers):
		return false
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	var workforce: int = available_workers
	if workforce < 0 and faction_domain.starting_workers.has(planet_id):
		workforce = int(faction_domain.starting_workers.get(planet_id, 0))
	return economy_domain.purchase_upgrade(faction, planet_id, upgrade_id, workforce, effective_catalog)

func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	economy_domain.add_planet_upgrade(planet_id, upgrade_id)

func has_worker_factory(planet_id: StringName) -> bool:
	return economy_domain.has_worker_factory(planet_id)

func can_build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int, credit_cost: int = 5) -> bool:
	var faction: StringName = faction_of(planet_id)
	return economy_domain.can_build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		has_scanned_planet(faction),
		has_technology(faction, TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)

func build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int, credit_cost: int = 5) -> bool:
	var faction: StringName = faction_of(planet_id)
	var built: bool = economy_domain.build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		has_scanned_planet(faction),
		has_technology(faction, TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)
	if built:
		mark_milestone(faction, &"first_worker_factory")
	return built

func register_gathering_workers(faction: StringName, planet_id: StringName, worker_amount: int, source_planet_id: StringName = &"") -> int:
	if faction == FACTION_NEUTRAL or faction.is_empty() or faction_of(planet_id) != FACTION_NEUTRAL or not has_scanned_planet(faction, planet_id):
		return 0
	economy_domain.register_gathering_workers(faction, planet_id, source_planet_id, worker_amount)
	return economy_domain.gathering_workers_on(faction, planet_id)

func get_reserved_workers(planet_id: StringName) -> int:
	return economy_domain.reserved_workers_on(planet_id)

func get_available_workers(planet_id: StringName, total_workers: int) -> int:
	return economy_domain.available_workers(planet_id, total_workers)

func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	return economy_domain.reserve_workers(planet_id, job_id, amount, total_workers)

func release_workers(planet_id: StringName, job_id: StringName) -> int:
	return economy_domain.release_workers(planet_id, job_id)

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
func ensure_starter_research_ship(faction: StringName, planet_id: StringName) -> StringName:
	return ship_domain.ensure_starter_research_ship(faction, planet_id, DEFAULT_SHIP_PART_CATALOG)

func mark_research_ship_departed(ship_id: StringName) -> bool:
	return ship_domain.mark_research_ship_departed(ship_id)

func mark_research_ship_arrived(ship_id: StringName, planet_id: StringName) -> bool:
	return ship_domain.mark_research_ship_arrived(ship_id, planet_id)

func get_research_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_research_ship_records(faction)

func register_persistent_fleet(fleet: FleetSnapshot, status: StringName = &"in_transit") -> void:
	ship_domain.register_persistent_fleet(fleet, status)

func get_persistent_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_persistent_ship_records(faction)

func mark_persistent_ship_arrived(ship_id: StringName, planet_id: StringName, status: StringName = &"idle") -> bool:
	return ship_domain.mark_persistent_ship_arrived(ship_id, planet_id, status)

func mark_persistent_ship_lost(ship_id: StringName) -> bool:
	return ship_domain.mark_persistent_ship_lost(ship_id)

func get_research_missions(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_research_missions(faction)

func queue_research_mission(faction: StringName, target_planet_id: StringName, task_type: StringName, duration: float = 2.0) -> StringName:
	return ship_domain.queue_research_mission(faction, target_planet_id, task_type, duration)

func cancel_research_mission(mission_id: StringName) -> bool:
	return ship_domain.cancel_research_mission(mission_id)

func get_persistent_ship(ship_id: StringName) -> RefCounted:
	return ship_domain.get_persistent_ship(ship_id)

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

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
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

func launch_ship(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
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

func reconcile_defender_fleet(planet_id: StringName, defender_fleet: FleetSnapshot, surviving: Array[ShipAssembly]) -> void:
	ship_domain.reconcile_defender_fleet(planet_id, defender_fleet, surviving)

# --- GRID BUILDINGS, LOCAL RESOURCES & CAPTURE DELEGATES ---
func can_place_planet_building(planet_id: StringName, building_id: StringName, catalog: BuildingCatalog = null) -> bool:
	var faction: StringName = faction_of(planet_id)
	if faction == FACTION_NEUTRAL:
		return false
	var cat: BuildingCatalog = catalog if catalog != null else DEFAULT_BUILDING_CATALOG
	if cat == null:
		return false
	var building: BuildingDefinition = cat.resolve(building_id)
	if building == null:
		return false
	if not String(building.required_tech_id).is_empty() and not has_technology(faction, building.required_tech_id):
		return false
	return economy_domain.can_spend_building_cost(faction, building)

func place_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int, catalog: BuildingCatalog = null) -> bool:
	if not can_place_planet_building(planet_id, building_id, catalog):
		return false
	var cat: BuildingCatalog = catalog if catalog != null else DEFAULT_BUILDING_CATALOG
	var building: BuildingDefinition = cat.resolve(building_id)
	var faction: StringName = faction_of(planet_id)
	var job_id := StringName("building_%s_%d_%d" % [String(building_id), q, r])
	if economy_domain.building_job_in_progress(planet_id, q, r) or economy_domain.planet_building_at(planet_id, q, r) != &"":
		return false
	var total_workers: int = maxi(int(faction_domain.starting_workers.get(planet_id, 0)), building.workers_required)
	if building.workers_required > 0 and not economy_domain.reserve_workers(planet_id, job_id, building.workers_required, total_workers):
		return false
	if not economy_domain.spend_building_cost(faction, building):
		economy_domain.release_workers(planet_id, job_id)
		return false
	if building.build_time > 0.0:
		var queued: bool = economy_domain.queue_planet_building(
			planet_id, building_id, q, r, faction, job_id, building.build_time,
			{"resources": building.cost_resources, "credits": building.credit_cost}
		)
		if queued:
			return true
		# Roll back an impossible queue without leaking costs or labor.
		economy_domain.release_workers(planet_id, job_id)
		for resource_id in building.cost_resources:
			economy_domain.add_faction_resource(faction, resource_id as StringName, int(building.cost_resources[resource_id]))
		economy_domain.add_faction_credits(faction, building.credit_cost)
		return false
	economy_domain.release_workers(planet_id, job_id)
	economy_domain.record_planet_building(planet_id, building_id, q, r)
	return true

func remove_planet_building(planet_id: StringName, q: int, r: int) -> bool:
	return not String(economy_domain.remove_planet_building(planet_id, q, r)).is_empty()

func planet_building_at(planet_id: StringName, q: int, r: int) -> StringName:
	return economy_domain.planet_building_at(planet_id, q, r)

func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return economy_domain.get_local_resource(planet_id, resource_id)

func get_local_resources(planet_id: StringName) -> Dictionary:
	return economy_domain.local_vault(planet_id).duplicate()

func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	return economy_domain.add_local_resource(planet_id, resource_id, amount)

func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.spend_local_resource(planet_id, resource_id, amount)

func can_spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return amount >= 0 and economy_domain.get_local_resource(planet_id, resource_id) >= amount

func transfer_local_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.transfer_resources(from_planet, to_planet, resource_id, amount)

func deal_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.seed_local_resources(planet_ids, pool, seed_value)

func can_register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> bool:
	return economy_domain.can_register_trade_route(from_planet, to_planet, resource_id)

func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	return economy_domain.register_trade_route(from_planet, to_planet, resource_id)

func tick_trade_routes() -> int:
	return economy_domain.tick_trade_routes()

func trade_routes_snapshot() -> Dictionary:
	return economy_domain.trade_routes_snapshot()

func capture_planet(planet_id: StringName, decision: StringName, faction: StringName) -> void:
	match decision:
		&"loot":
			steal_resources(planet_id, faction, 0.5)
		&"neutralize":
			set_faction(planet_id, FACTION_NEUTRAL)
		_:
			set_faction(planet_id, faction)

func steal_resources(planet_id: StringName, attacker_faction: StringName, percentage: float = 0.5) -> Dictionary:
	var stolen: Dictionary = {}
	var vault := economy_domain.local_vault(planet_id).duplicate()
	for resource_id in vault:
		var amount: int = int(vault[resource_id])
		if amount <= 0:
			continue
		var take: int = maxi(1, int(round(float(amount) * clampf(percentage, 0.0, 1.0))))
		if take <= 0:
			continue
		economy_domain.spend_local_resource(planet_id, resource_id as StringName, take)
		economy_domain.add_faction_resource(attacker_faction, resource_id as StringName, take)
		stolen[resource_id] = take
	return stolen

# --- SAVE / LOAD SNAPSHOTS ---

## Captures the full run state as a pure-data RunSaveData resource. The world
## scene is not required: everything lives in the domains, transit records and
## the chunk cache. Runtime-only objects (PersistentShipRecord, ResearchMission)
## are flattened into serializable dictionaries.
func snapshot_run() -> RunSaveData:
	var data := RunSaveData.new()
	data.save_version = RunSaveData.SAVE_VERSION
	data.session = session().copy()
	# Faction
	data.ownership = faction_domain.ownership.duplicate(true)
	data.homeworlds = faction_domain.homeworlds.duplicate(true)
	data.starting_workers = faction_domain.starting_workers.duplicate(true)
	data.known_planets = faction_domain.known_planets.duplicate(true)
	data.scanned_planets = faction_domain.scanned_planets.duplicate(true)
	data.scan_intel = faction_domain.scan_intel.duplicate(true)
	data.milestones = faction_domain.milestones.duplicate(true)
	# Economy
	data.faction_vaults = economy_domain.faction_vaults.duplicate(true)
	data.faction_credits = economy_domain.faction_credits.duplicate(true)
	data.worker_reservations = economy_domain.worker_reservations.duplicate(true)
	data.upgrade_build_jobs = economy_domain.upgrade_build_jobs.duplicate(true)
	data.planet_resources = economy_domain.planet_resources.duplicate(true)
	data.planet_upgrades = economy_domain.planet_upgrades.duplicate(true)
	data.worker_factories = economy_domain.worker_factories.duplicate(true)
	data.gathering_workers = economy_domain.gathering_workers.duplicate(true)
	data.gathering_sources = economy_domain.gathering_sources.duplicate(true)
	data.local_vaults = economy_domain.local_vaults.duplicate(true)
	data.trade_routes = economy_domain.trade_routes.duplicate(true)
	data.planet_buildings = economy_domain.planet_buildings.duplicate(true)
	data.building_jobs = economy_domain.building_jobs.duplicate(true)
	data.local_seeded_planets = economy_domain._local_seeded_planets.duplicate(true)
	data.worker_transport_records = economy_domain.worker_transport_records.duplicate(true)
	data.next_trade_route_index = economy_domain._next_trade_route_index
	data.next_worker_transport_index = economy_domain._next_worker_transport_index
	# Tech
	data.researched_techs = tech_domain.researched_techs.duplicate(true)
	data.planet_technologies = tech_domain.planet_technologies.duplicate(true)
	data.research_jobs = tech_domain.research_jobs.duplicate(true)
	# Ship
	data.ship_part_inventory = ship_domain.ship_part_inventory.duplicate(true)
	data.ship_assemblies = ship_domain.ship_assemblies.duplicate(true)
	data.ship_build_jobs = ship_domain.ship_build_jobs.duplicate(true)
	data.persistent_ships = _snapshot_persistent_ships()
	data.research_missions = _snapshot_research_missions()
	data.next_ship_index = ship_domain.next_ship_index
	data.next_research_mission_index = ship_domain.next_research_mission_index
	# Transits
	for record_value in _transit_records.values():
		var record: TransitRecord = record_value as TransitRecord
		if record != null:
			data.transits.append(record.copy())
	data.next_transit_index = _next_transit_index
	# Chunk world + timers
	data.chunk_data = _capture_chunk_data()
	data.timers = _capture_timers().duplicate()
	return data

## Restores a snapshot into the domains and marks the world for reconnect on
## the next world-scene boot. The chunk payload and pacing timers are handed to
## the world scene via consume_pending_* accessors.
func restore_run(data: RunSaveData) -> bool:
	if data == null:
		return false
	_run_active = true
	_reconnect_requested = true
	_pending_battle = null
	if data.session != null:
		_session = data.session.copy()
		_run_id = _session.run_id
		_run_scenario_id = _session.scenario_id
		_run_layout_seed = _session.layout_seed
		_run_infinite_world = _session.infinite_world
	else:
		_run_id = &""
		_run_scenario_id = &""
		_run_layout_seed = 0
		_run_infinite_world = false
	# Faction
	faction_domain.reset_infinite()
	faction_domain.ownership = _restore_dict(data.ownership)
	faction_domain.homeworlds = _restore_dict(data.homeworlds)
	faction_domain.starting_workers = _restore_dict(data.starting_workers)
	faction_domain.known_planets = _restore_dict(data.known_planets)
	faction_domain.scanned_planets = _restore_dict(data.scanned_planets)
	faction_domain.scan_intel = _restore_dict(data.scan_intel)
	faction_domain.milestones = _restore_dict(data.milestones)
	# Economy
	economy_domain.reset()
	economy_domain.faction_vaults = _restore_dict(data.faction_vaults)
	economy_domain.faction_credits = _restore_dict(data.faction_credits)
	economy_domain.worker_reservations = _restore_dict(data.worker_reservations)
	economy_domain.upgrade_build_jobs = _restore_dict(data.upgrade_build_jobs)
	economy_domain.planet_resources = _restore_dict(data.planet_resources)
	economy_domain.planet_upgrades = _restore_dict(data.planet_upgrades)
	economy_domain.worker_factories = _restore_dict(data.worker_factories)
	economy_domain.gathering_workers = _restore_dict(data.gathering_workers)
	economy_domain.gathering_sources = _restore_dict(data.gathering_sources)
	economy_domain.local_vaults = _restore_dict(data.local_vaults)
	economy_domain.trade_routes = _restore_dict(data.trade_routes)
	economy_domain.planet_buildings = _restore_dict(data.planet_buildings)
	economy_domain.building_jobs = _restore_dict(data.building_jobs)
	economy_domain._local_seeded_planets = _restore_dict(data.local_seeded_planets)
	economy_domain.worker_transport_records = _restore_dict(data.worker_transport_records)
	economy_domain._next_trade_route_index = data.next_trade_route_index
	economy_domain._next_worker_transport_index = data.next_worker_transport_index
	# Tech
	tech_domain.reset()
	tech_domain.researched_techs = _restore_dict(data.researched_techs)
	tech_domain.planet_technologies = _restore_dict(data.planet_technologies)
	tech_domain.research_jobs = _restore_dict(data.research_jobs)
	# Ship
	ship_domain.reset()
	ship_domain.ship_part_inventory = _restore_dict(data.ship_part_inventory)
	ship_domain.ship_assemblies = _restore_dict(data.ship_assemblies)
	ship_domain.ship_build_jobs = _restore_dict(data.ship_build_jobs)
	_restore_persistent_ships(data.persistent_ships)
	_restore_research_missions(data.research_missions)
	ship_domain.next_ship_index = data.next_ship_index
	ship_domain.next_research_mission_index = data.next_research_mission_index
	# Transits
	_transit_records.clear()
	for record in data.transits:
		if record != null:
			_transit_records[record.transit_id] = record.copy()
	_next_transit_index = data.next_transit_index
	# Chunk world + timers (consumed by the world scene on boot)
	_pending_chunk_data = data.chunk_data
	_pending_timers = data.timers.duplicate()
	return true

func pending_chunk_data() -> ChunkSaveData:
	return _pending_chunk_data

func consume_pending_chunk_data() -> ChunkSaveData:
	var data: ChunkSaveData = _pending_chunk_data
	_pending_chunk_data = null
	return data

func pending_timers() -> Dictionary:
	return _pending_timers.duplicate()

func consume_pending_timers() -> Dictionary:
	var timers: Dictionary = _pending_timers.duplicate()
	_pending_timers.clear()
	return timers

func _capture_chunk_data() -> ChunkSaveData:
	var coordinator: Node = _find_chunk_coordinator()
	if coordinator != null and coordinator.has_method("save_state"):
		return coordinator.call("save_state") as ChunkSaveData
	return null

func _capture_timers() -> Dictionary:
	var economy_manager: Node = _find_economy_manager()
	if economy_manager == null:
		return {}
	var result: Dictionary = {}
	if economy_manager.has_method("economy_tick_remaining"):
		result["economy_remaining"] = float(economy_manager.call("economy_tick_remaining"))
	if economy_manager.has_method("gather_tick_remaining"):
		result["gather_remaining"] = float(economy_manager.call("gather_tick_remaining"))
	return result

func _find_chunk_coordinator() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	return _find_node_with_method(scene, "save_state", "ChunkCoordinator")

func _find_economy_manager() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	return _find_node_with_method(scene, "restore_timer_remaining", "PlanetEconomyManager")

func _find_node_with_method(node: Node, method: String, class_hint: String) -> Node:
	if node == null:
		return null
	if node.has_method(method):
		var script: Script = node.get_script()
		if script != null and String(script.get_global_name()) == class_hint:
			return node
	for child in node.get_children():
		var found: Node = _find_node_with_method(child, method, class_hint)
		if found != null:
			return found
	return null

func _snapshot_persistent_ships() -> Dictionary:
	var result: Dictionary = {}
	for ship_id in ship_domain.persistent_ships:
		var record: ShipDomain.PersistentShipRecord = ship_domain.persistent_ships[ship_id] as ShipDomain.PersistentShipRecord
		if record == null:
			continue
		result[ship_id] = {
			"faction": record.faction,
			"mission_role": record.mission_role,
			"current_planet_id": record.current_planet_id,
			"status": record.status,
			"active_mission_id": record.active_mission_id,
			"fleet": record.fleet.copy() if record.fleet != null else null,
		}
	return result

func _snapshot_research_missions() -> Dictionary:
	var result: Dictionary = {}
	for mission in ship_domain.research_missions:
		if mission == null:
			continue
		result[String(mission.mission_id)] = {
			"mission_id": mission.mission_id,
			"target_planet_id": mission.target_planet_id,
			"task_type": mission.task_type,
			"duration": mission.duration,
			"remaining": mission.remaining,
			"status": mission.status,
		}
	return result

func _restore_persistent_ships(source: Dictionary) -> void:
	ship_domain.persistent_ships.clear()
	for key in source:
		var ship_id := StringName(key)
		var entry: Dictionary = source[key] as Dictionary
		if entry == null:
			continue
		var record := ShipDomain.PersistentShipRecord.new()
		record.ship_id = ship_id
		record.faction = StringName(entry.get("faction", &""))
		record.mission_role = StringName(entry.get("mission_role", &""))
		record.current_planet_id = StringName(entry.get("current_planet_id", &""))
		record.status = StringName(entry.get("status", &"idle"))
		record.active_mission_id = StringName(entry.get("active_mission_id", &""))
		record.fleet = entry.get("fleet") as FleetSnapshot
		ship_domain.persistent_ships[ship_id] = record

func _restore_research_missions(source: Dictionary) -> void:
	ship_domain.research_missions.clear()
	for key in source:
		var entry: Dictionary = source[key] as Dictionary
		if entry == null:
			continue
		var mission := ShipDomain.ResearchMission.new()
		mission.mission_id = StringName(entry.get("mission_id", &""))
		mission.target_planet_id = StringName(entry.get("target_planet_id", &""))
		mission.task_type = StringName(entry.get("task_type", &"scan"))
		mission.duration = float(entry.get("duration", 1.0))
		mission.remaining = float(entry.get("remaining", mission.duration))
		mission.status = StringName(entry.get("status", &"queued"))
		ship_domain.research_missions.append(mission)

## Deep-restores a dictionary, converting String keys back to StringName so
## domain lookups behave exactly like the pre-save state. Int keys stay ints.
func _restore_dict(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		var new_key: Variant = key
		if key is String:
			new_key = StringName(key)
		var value: Variant = source[key]
		if value is Dictionary:
			value = _restore_dict(value)
		elif value is Array:
			value = _restore_array(value)
		result[new_key] = value
	return result

func _restore_array(source: Array) -> Array:
	var result := []
	for item in source:
		if item is Dictionary:
			result.append(_restore_dict(item))
		elif item is Array:
			result.append(_restore_array(item))
		else:
			result.append(item)
	return result

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
